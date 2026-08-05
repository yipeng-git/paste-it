import AppKit
import QuartzCore
import SwiftUI

enum TimelinePanelOpenSource: String {
    case hotkey
    case statusItem = "status_item"
    case menu
}

@MainActor
final class TimelinePanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let pasteController: PasteController
    private var panel: NSPanel?
    private var globalOutsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var isAnimating = false
    var onShow: (() -> Void)?
    /// Set by AppRuntime so outside-click dismiss can ignore detached edit/preview windows.
    weak var detachedWindowController: ClipDetachedWindowController?
    weak var pasteStackPanelController: PasteStackPanelController?

    private let panelHeight: CGFloat = 320
    private let bottomInset: CGFloat = 12
    private let animationDuration: CFTimeInterval = 0.28

    init(appState: AppState, pasteController: PasteController) {
        self.appState = appState
        self.pasteController = pasteController
        super.init()
    }

    func toggle(source: TimelinePanelOpenSource) {
        if panel?.isVisible == true {
            hide()
        } else {
            show(source: source)
        }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// Screen frame of the floating timeline panel (bubble anchors above this).
    var panelFrame: NSRect? {
        panel?.frame
    }

    /// Clears first responder so space-bar / shortcuts aren't eaten by the search field.
    func resignFirstResponder() {
        panel?.makeFirstResponder(nil)
    }

    func restoreKeyFocus() {
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
        panel.makeFirstResponder(nil)
    }

    func show(source: TimelinePanelOpenSource = .menu) {
        onShow?()
        guard !isAnimating else { return }
        let wasVisible = panel?.isVisible == true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        appState.resetFiltersForPanelShow()

        let finalFrame = targetFrame(for: panel)
        let startFrame: NSRect
        if let screen = screenForCurrentFocus() {
            startFrame = panelSlideOffscreenFrame(from: finalFrame, screen: screen)
        } else {
            var fallback = finalFrame
            fallback.origin.y -= finalFrame.height
            startFrame = fallback
        }
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 1

        // nonactivatingPanel + orderFrontRegardless keeps the previous app focused
        // so the user can immediately ⌘V after staging a clip (Paste-like).
        // makeKey() still allows the search field to accept typing.
        panel.orderFrontRegardless()
        panel.makeKey()
        // Prevent SwiftUI from parking first-responder in the search field.
        panel.makeFirstResponder(nil)
        startOutsideClickMonitoring()

        if !wasVisible {
            Analytics.beginPanelSession(
                source: source.rawValue,
                historyCount: appState.historyStore.clips.count
            )
        }

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isAnimating = false
                // Defer out of the display-cycle flush — mutating @Published
                // mid-layout was crashing under exclusivity checking.
                DispatchQueue.main.async {
                    self.panel?.makeFirstResponder(nil)
                    self.appState.searchBlurRequest += 1
                    NSLog("PasteIt: timeline panel shown")
                }
            }
        })
    }

    func hide(completion: (@Sendable () -> Void)? = nil) {
        guard let panel, panel.isVisible, !isAnimating else {
            if panel?.isVisible != true {
                stopOutsideClickMonitoring()
            }
            completion?()
            return
        }

        // Detached edit windows stay open on their own; preview bubble is timeline-anchored.
        if appState.previewClip != nil {
            appState.dismissPreview()
        }
        isAnimating = true
        stopOutsideClickMonitoring()

        let endFrame: NSRect
        if let screen = panel.screen ?? screenForCurrentFocus() {
            endFrame = panelSlideOffscreenFrame(from: panel.frame, screen: screen)
        } else {
            var fallback = panel.frame
            fallback.origin.y -= fallback.height
            endFrame = fallback
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
            // Fade alongside the slide: when a display below forces the slide to
            // clamp at the screen edge, the fade carries the dismissal.
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
                self?.isAnimating = false
                Analytics.endPanelSession()
                completion?()
            }
        })
    }

    private func makePanel() -> NSPanel {
        let contentView = TimelineView(appState: appState, pasteController: pasteController)
        let hostingController = NSHostingController(rootView: contentView)

        let panel = FloatingTimelinePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Paste It"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = hostingController
        panel.delegate = self
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false

        // AppKit-level continuous clip: SwiftUI glass alone does not clear the
        // rectangular hosting surface, which shows as opaque corner "ears".
        PanelCornerMask.apply(to: hostingController.view)
        PanelCornerMask.apply(to: panel.contentView)

        return panel
    }

    private func targetFrame(for panel: NSPanel) -> NSRect {
        guard let screen = screenForCurrentFocus() else {
            return panel.frame
        }
        // Sit just above the Dock / menu-safe area with a small breathing gap.
        let visibleFrame = screen.visibleFrame
        let width = min(1120, max(640, visibleFrame.width - 32))
        let height = panelHeight
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY + bottomInset
        )
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    private func screenForCurrentFocus() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.hideIfMouseIsOutsidePanel()
            }
        }

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }

            if self.shouldIgnoreOutsideClick(for: event) {
                return event
            }

            // Peek matrix: clicks on the timeline while a bubble is open.
            // Same card / chrome → dismiss; other card → let selection retarget the bubble.
            if self.appState.previewClip != nil,
               event.window === self.panel,
               event.type == .leftMouseDown {
                self.handlePreviewOpenPanelClick()
                return event
            }

            if event.window !== self.panel {
                self.hide()
            }
            return event
        }
    }

    /// Resolve Space-preview dismiss vs retarget from a click on the timeline panel.
    private func handlePreviewOpenPanelClick() {
        let point = NSEvent.mouseLocation
        if let hitID = ClipCardFrameRegistry.cardID(atScreenPoint: point) {
            if hitID == appState.previewClip?.id {
                appState.dismissPreview()
            }
            // Different card: SwiftUI card tap selects → syncPreviewToSelection retargets.
            return
        }
        // Toolbar / blank / gaps — leave the peeked context.
        appState.dismissPreview()
    }

    private func stopOutsideClickMonitoring() {
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
        }
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
        }
        globalOutsideClickMonitor = nil
        localOutsideClickMonitor = nil
    }

    private func hideIfMouseIsOutsidePanel() {
        guard let panel, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        if panel.frame.contains(mouse) { return }
        // Clicks on detached edit/preview / Paste Stack should not dismiss the timeline.
        // Only count *visible* windows — ordered-out panels keep their last frame and would
        // otherwise swallow outside clicks (especially a centered preview bubble).
        if let detached = detachedWindowController {
            for window in NSApp.windows where detached.owns(window) && window.isVisible && window.frame.contains(mouse) {
                return
            }
        }
        if let stackPanel = pasteStackPanelController, stackPanel.isVisible {
            for window in NSApp.windows where stackPanel.owns(window) && window.isVisible && window.frame.contains(mouse) {
                return
            }
        }
        hide()
    }

    /// Ignore outside-dismiss when the click lands on a detached edit/preview window
    /// or any sheet/child of the timeline panel.
    private func shouldIgnoreOutsideClick(for event: NSEvent) -> Bool {
        guard let panel else { return false }
        if let window = event.window, detachedWindowController?.owns(window) == true {
            return true
        }
        if let window = event.window, pasteStackPanelController?.owns(window) == true {
            return true
        }
        guard let window = event.window else { return false }
        if window === panel { return false }
        if window.sheetParent === panel { return true }
        if panel.sheets.contains(where: { $0 === window }) { return true }
        if window.parent === panel { return true }
        return false
    }
}

private final class FloatingTimelinePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
