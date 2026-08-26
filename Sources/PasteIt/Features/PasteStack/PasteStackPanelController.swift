import AppKit
import QuartzCore
import SwiftUI

/// Floating Paste Stack rail on the trailing screen edge — vertical, not a second timeline.
@MainActor
final class PasteStackPanelController: NSObject, NSWindowDelegate {
    private let stack: PasteStackController
    private let historyStore: HistoryStore
    private var panel: NSPanel?
    private var isAnimating = false

    private let panelWidth = PasteStackPanelLayout.panelWidth
    private let trailingInset: CGFloat = 14
    private let verticalInset: CGFloat = 14
    private var minPanelHeight: CGFloat { PasteStackPanelLayout.minPanelHeight }
    private let defaultPanelHeight: CGFloat = 300

    init(stack: PasteStackController, historyStore: HistoryStore) {
        self.stack = stack
        self.historyStore = historyStore
        super.init()
        stack.onPanelSync = { [weak self] shouldShow in
            guard let self else { return }
            if shouldShow {
                // @ObservedObject already refreshes card content — only animate in when hidden.
                if !self.isVisible {
                    self.show()
                }
            } else {
                self.hide()
            }
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func owns(_ window: NSWindow?) -> Bool {
        window === panel
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // PasteStackView observes the stack via @ObservedObject — do not replace rootView.

        let finalFrame = targetFrame(for: panel)
        if panel.isVisible {
            panel.orderFrontRegardless()
            return
        }

        let startFrame: NSRect
        if let screen = screenForCurrentFocus() {
            startFrame = slideOffNearestEdge(from: finalFrame, screen: screen)
        } else {
            var fallback = finalFrame
            fallback.origin.x += finalFrame.width
            startFrame = fallback
        }
        panel.setFrame(startFrame, display: false)
        // Fade in so a left-edge slide doesn't flash on an adjacent display.
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.isAnimating = false }
        })
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        if !isAnimating {
            persistFrameIfNeeded()
        }
        isAnimating = true
        let endFrame: NSRect
        if let screen = panel.screen ?? screenForCurrentFocus() {
            endFrame = slideOffNearestEdge(from: panel.frame, screen: screen)
        } else {
            var fallback = panel.frame
            fallback.origin.x += fallback.width
            endFrame = fallback
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
                self?.isAnimating = false
            }
        })
    }

    /// Two short fades so opening the timeline reminds you the stack still owns ⌘V.
    func attentionPulse() {
        guard let panel, panel.isVisible, !isAnimating else { return }
        panel.orderFrontRegardless()
        Task { @MainActor in
            await self.animateAlpha(panel, to: 0.38, duration: 0.09)
            guard self.panel === panel, panel.isVisible else { return }
            await self.animateAlpha(panel, to: 1, duration: 0.12)
            guard self.panel === panel, panel.isVisible else { return }
            await self.animateAlpha(panel, to: 0.38, duration: 0.09)
            guard self.panel === panel, panel.isVisible else { return }
            await self.animateAlpha(panel, to: 1, duration: 0.14)
        }
    }

    private func animateAlpha(_ panel: NSPanel, to value: CGFloat, duration: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = value
            }, completionHandler: {
                continuation.resume()
            })
        }
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(
            rootView: PasteStackView(stack: stack, historyStore: historyStore)
        )
        hosting.sizingOptions = []
        let root = PasteStackRootViewController(hosting: hosting)
        let panel = PasteStackFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: defaultPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: panelWidth, height: minPanelHeight)
        panel.maxSize = NSSize(width: panelWidth, height: 10_000)
        panel.contentViewController = root
        panel.delegate = self
        PanelCornerMask.apply(to: root.view)
        PanelCornerMask.apply(to: panel.contentView)
        return panel
    }

    private func targetFrame(for panel: NSPanel) -> NSRect {
        guard let screen = screenForCurrentFocus() else {
            return panel.frame
        }
        let visible = screen.visibleFrame
        let placement = PasteStackPanelLayout.placement(for: screen)
            ?? PasteStackPanelLayout.migrateLegacyPlacement(on: screen)
        let height = clampedHeight(
            CGFloat(placement?.height ?? Double(defaultPanelHeight)),
            visible: visible
        )
        let defaultX = visible.maxX - panelWidth - trailingInset
        let defaultY = min(
            max(visible.minY + verticalInset, visible.midY - height / 2),
            visible.maxY - height - verticalInset
        )
        var x = placement.map { visible.minX + CGFloat($0.relX) } ?? defaultX
        var y = placement.map { visible.minY + CGFloat($0.relY) } ?? defaultY
        x = min(max(visible.minX + 8, x), visible.maxX - panelWidth - 8)
        y = min(max(visible.minY + 8, y), visible.maxY - height - 8)
        return NSRect(x: x, y: y, width: panelWidth, height: height)
    }

    private func clampedHeight(_ height: CGFloat, visible: NSRect) -> CGFloat {
        let maxH = max(minPanelHeight, visible.height - (verticalInset * 2))
        return min(max(minPanelHeight, height), maxH)
    }

    private func persistFrameIfNeeded() {
        guard let panel, panel.isVisible, !isAnimating else { return }
        PasteStackPanelLayout.persistFrame(panel)
    }

    /// Park just off the nearer left/right edge of this screen.
    private func slideOffNearestEdge(from onscreen: NSRect, screen: NSScreen) -> NSRect {
        var off = onscreen
        let visible = screen.visibleFrame
        let distLeading = onscreen.midX - visible.minX
        let distTrailing = visible.maxX - onscreen.midX
        if distLeading < distTrailing {
            off.origin.x = visible.minX - onscreen.width - 12
        } else {
            off.origin.x = visible.maxX + 12
        }
        return off
    }

    private func screenForCurrentFocus() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stack.close()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard panel?.inLiveResize != true else { return }
        persistFrameIfNeeded()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrameIfNeeded()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let visible = sender.screen?.visibleFrame ?? screenForCurrentFocus()?.visibleFrame
        let maxH = (visible?.height ?? 900) - 24
        return NSSize(
            width: panelWidth,
            height: min(max(minPanelHeight, frameSize.height), maxH)
        )
    }
}

private final class PasteStackFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts SwiftUI and a sibling AppKit grip so resize isn't inside the SwiftUI tree.
private final class PasteStackRootViewController: NSViewController {
    private let hosting: NSHostingController<PasteStackView>

    init(hosting: NSHostingController<PasteStackView>) {
        self.hosting = hosting
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(hosting.view)

        let grip = PasteStackHeightGripView()
        grip.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(grip)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: root.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            grip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            grip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            grip.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            grip.heightAnchor.constraint(equalToConstant: PasteStackPanelLayout.gripHeight)
        ])
        view = root
    }
}

/// Transparent hit target over the visual bar. Starts AppKit's own south-edge live resize.
private final class PasteStackHeightGripView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // Pin the event to the bottom edge so AppKit resizes like a window chrome drag.
        // `_resizeWithEvent:` runs a tracking loop until mouse-up (same as a real edge drag).
        let edgeEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: event.locationInWindow.x, y: 1),
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: 1,
            pressure: event.pressure
        )
        let selector = NSSelectorFromString("_resizeWithEvent:")
        if let edgeEvent, window.responds(to: selector) {
            window.perform(selector, with: edgeEvent)
        }
    }
}

enum PasteStackPanelLayout {
    static let panelWidth: CGFloat = 236
    static let rowHeight: CGFloat = 52
    static let rowSpacing: CGFloat = 6
    static let listPaddingVertical: CGFloat = 6
    static let gripHeight: CGFloat = 22
    static let toolbarHeight: CGFloat = 70
    static let minVisibleRows = 3

    static let placementsKey = "pasteStack.panel.placementsByDisplay"
    static let heightKey = "pasteStack.panel.height"
    static let originXKey = "pasteStack.panel.originX"
    static let originYKey = "pasteStack.panel.originY"

    struct ScreenPlacement: Codable, Equatable {
        var relX: Double
        var relY: Double
        var height: Double
    }

    static var minPanelHeight: CGFloat {
        let list = rowHeight * CGFloat(minVisibleRows)
            + rowSpacing * CGFloat(minVisibleRows - 1)
            + listPaddingVertical
        return toolbarHeight + list + gripHeight
    }

    static func displayID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return String(number.uint32Value)
        }
        return screen.localizedName
    }

    static func placement(for screen: NSScreen) -> ScreenPlacement? {
        loadPlacements()[displayID(for: screen)]
    }

    /// One-time: reuse the old global origin if it actually sits on this screen.
    static func migrateLegacyPlacement(on screen: NSScreen) -> ScreenPlacement? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: originXKey) != nil else { return nil }
        let x = CGFloat(defaults.double(forKey: originXKey))
        let y = CGFloat(defaults.double(forKey: originYKey))
        let height = defaults.object(forKey: heightKey) as? Double
        let visible = screen.visibleFrame
        let point = NSPoint(x: x, y: y)
        guard visible.insetBy(dx: -80, dy: -80).contains(point) else { return nil }
        let placement = ScreenPlacement(
            relX: Double(x - visible.minX),
            relY: Double(y - visible.minY),
            height: height ?? Double(300)
        )
        save(placement, for: screen)
        return placement
    }

    @MainActor
    static func persistFrame(_ window: NSWindow) {
        let frame = window.frame
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Ignore frames parked off either edge (slide animation).
        if frame.minX >= visible.maxX - 4 { return }
        if frame.maxX <= visible.minX + 4 { return }
        save(
            ScreenPlacement(
                relX: Double(frame.origin.x - visible.minX),
                relY: Double(frame.origin.y - visible.minY),
                height: Double(frame.height)
            ),
            for: screen
        )
    }

    private static func loadPlacements() -> [String: ScreenPlacement] {
        guard let data = UserDefaults.standard.data(forKey: placementsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: ScreenPlacement].self, from: data)) ?? [:]
    }

    private static func save(_ placement: ScreenPlacement, for screen: NSScreen) {
        var all = loadPlacements()
        all[displayID(for: screen)] = placement
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: placementsKey)
        }
    }
}
