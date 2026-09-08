import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Toast geometry is independent of the timeline's content and fixed 320-point height.
enum RemovalToastPlacement {
    static let gap: CGFloat = 12
    static let screenInset: CGFloat = 12

    static func maximumWidth(parent: NSRect, screen: NSRect) -> CGFloat {
        max(120, min(450, parent.width - 32, screen.width - screenInset * 2))
    }

    static func frame(size: NSSize, parent: NSRect, screen: NSRect) -> NSRect {
        let width = min(size.width, screen.width - screenInset * 2)
        let height = min(size.height, screen.height - screenInset * 2)
        let x = min(max(parent.midX - width / 2, screen.minX + screenInset), screen.maxX - screenInset - width)
        let y = min(max(parent.maxY + gap, screen.minY + screenInset), screen.maxY - screenInset - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

/// A non-key child panel: Undo clicks belong to the timeline and never activate Paste It.
@MainActor
final class RemovalToastPanelController {
    private let appState: AppState
    private weak var parent: NSWindow?
    private var panel: RemovalToastPanel?
    private var hosting: NSHostingController<RemovalToastView>?
    private var feedbackObservation: AnyCancellable?
    private var windowObservations: [AnyCancellable] = []
    private var animationGeneration = 0

    init(appState: AppState) {
        self.appState = appState
        feedbackObservation = appState.removalFeedback.$toast
            .combineLatest(appState.historyStore.$latestRemovalID)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func attach(to parent: NSWindow) {
        hide(animated: false)
        self.parent = parent
        windowObservations = [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                              NSWindow.didChangeScreenNotification].map { name in
            NotificationCenter.default.publisher(for: name, object: parent)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
        }
    }

    var visibleFrame: NSRect? {
        guard let panel, panel.isVisible else { return nil }
        return panel.frame
    }

    func refresh() {
        guard let parent, parent.isVisible, let toast = appState.removalFeedback.toast else {
            hide()
            return
        }
        let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        var view = RemovalToastView(
            toast: toast,
            canUndo: toast.removalID != nil && toast.removalID == appState.historyStore.latestRemovalID,
            onUndo: { [weak appState] id in appState?.undoLastRemoval(expectedID: id) },
            onHover: { [weak appState] hovered in appState?.removalFeedback.setHovered(hovered) }
        )
        let hosting: NSHostingController<RemovalToastView>
        if let existing = self.hosting {
            hosting = existing
            hosting.rootView = view
        } else {
            hosting = NSHostingController(rootView: view)
            hosting.sizingOptions = []
            self.hosting = hosting
        }
        let maxWidth = RemovalToastPlacement.maximumWidth(parent: parent.frame, screen: screen)
        var fitted = hosting.sizeThatFits(in: NSSize(width: maxWidth, height: 100))
        // Decide before mounting: ViewThatFits can switch branches when the window's
        // final pixel-rounded width differs from the detached hosting measurement.
        if fitted.width > maxWidth {
            view.multiline = true
            hosting.rootView = view
            fitted = hosting.sizeThatFits(in: NSSize(width: maxWidth, height: 100))
        }
        let size = NSSize(width: min(maxWidth, ceil(fitted.width) + 2), height: ceil(fitted.height))
        view.layoutSize = size
        hosting.rootView = view
        let frame = RemovalToastPlacement.frame(size: size, parent: parent.frame, screen: screen)
        let panel = self.panel ?? makePanel(hosting: hosting)
        self.panel = panel
        let wasVisible = panel.isVisible
        animationGeneration += 1
        panel.setFrame(frame, display: true)
        // Synthetic screenshot parents ignore input; their toast must do the same.
        panel.ignoresMouseEvents = parent.ignoresMouseEvents
        if panel.parent !== parent { parent.addChildWindow(panel, ordered: .above) }
        panel.alphaValue = wasVisible ? 1 : 0
        panel.orderFrontRegardless()
        if !wasVisible {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if !reduceMotion { panel.setFrameOrigin(NSPoint(x: frame.minX, y: frame.minY - 6)) }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide(animated: Bool = true) {
        guard let panel else { return }
        animationGeneration += 1
        let generation = animationGeneration
        guard animated, panel.isVisible,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.animationGeneration == generation else { return }
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel(hosting: NSHostingController<RemovalToastView>) -> RemovalToastPanel {
        let panel = RemovalToastPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.title = "Paste It"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = parent?.level ?? .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The native glass supplies its own depth. A second window shadow makes
        // this small surface look like a heavy opaque panel.
        panel.hasShadow = false
        panel.contentViewController = hosting
        return panel
    }
}

private final class RemovalToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
