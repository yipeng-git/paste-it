import AppKit
import Combine
import SwiftUI

/// Owns the standalone edit / preview panels so they never overlay or block the timeline.
@MainActor
final class ClipDetachedWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var editWindow: NSPanel?
    private var previewWindow: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    /// Prevents re-entrant AppState writes while a Combine delivery is in flight.
    private var isApplyingState = false
    /// Used to return key focus after inline editing in the preview bubble.
    weak var timelinePanelController: TimelinePanelController?

    private let editSize = NSSize(width: 680, height: 520)
    /// Gap between timeline panel top edge and bubble bottom.
    private let bubbleGap: CGFloat = 8

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func start() {
        appState.$editingClip
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.schedule { $0.syncEditWindow(with: item) }
            }
            .store(in: &cancellables)

        appState.$previewClip
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.schedule { $0.syncPreviewWindow(with: item) }
            }
            .store(in: &cancellables)
    }

    func owns(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === editWindow || window === previewWindow
    }

    private func schedule(_ work: @escaping (ClipDetachedWindowController) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            work(self)
        }
    }

    // MARK: - Edit

    private func syncEditWindow(with item: ClipItem?) {
        guard let item else {
            closeEditWindow()
            return
        }

        if appState.previewClip != nil, !isApplyingState {
            isApplyingState = true
            appState.previewClip = nil
            isApplyingState = false
        }

        let root = ClipEditView(item: item, historyStore: appState.historyStore) { [weak self] in
            self?.scheduleClearEditing()
        }
        presentEdit(root, size: editSize, title: "Edit Clip")
    }

    private func closeEditWindow() {
        guard let window = editWindow, window.isVisible else { return }
        window.orderOut(nil)
    }

    private func scheduleClearEditing() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.appState.editingClip != nil else { return }
            self.isApplyingState = true
            self.appState.editingClip = nil
            self.isApplyingState = false
        }
    }

    // MARK: - Preview bubble

    private func syncPreviewWindow(with item: ClipItem?) {
        guard let item else {
            closePreviewWindow()
            return
        }
        if appState.editingClip != nil {
            if !isApplyingState {
                isApplyingState = true
                appState.previewClip = nil
                isApplyingState = false
            }
            return
        }

        let frame = bubbleFrame(for: item)
        let root = ClipQuickPreview(
            item: item,
            historyStore: appState.historyStore,
            onClose: { [weak self] in
                self?.scheduleClearPreview()
            },
            onEditingChanged: { [weak self] editing in
                self?.setPreviewKeyFocus(editing)
            }
        )

        presentBubble(root, frame: frame)
    }

    private func closePreviewWindow() {
        guard let window = previewWindow, window.isVisible else { return }
        window.orderOut(nil)
        timelinePanelController?.restoreKeyFocus()
    }

    private func scheduleClearPreview() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.appState.previewClip != nil else { return }
            self.isApplyingState = true
            self.appState.previewClip = nil
            self.isApplyingState = false
        }
    }

    private func setPreviewKeyFocus(_ wantsKey: Bool) {
        guard let previewWindow else { return }
        if wantsKey {
            previewWindow.makeKey()
        } else {
            timelinePanelController?.restoreKeyFocus()
        }
    }

    /// Bottom edge sits just above the timeline panel; height grows upward with content.
    private func bubbleFrame(for item: ClipItem) -> NSRect {
        let screen = screenForBubble()
        let visible = screen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let margin: CGFloat = 8

        let timeline = timelinePanelController?.panelFrame
        let midX = timeline?.midX ?? visible.midX
        // Panel top in AppKit coords; bubble minY anchors here and grows upward.
        let panelTop = timeline?.maxY ?? (visible.minY + 332)
        let availableAbove = max(160, visible.maxY - margin - (panelTop + bubbleGap))

        let size = PreviewBubbleMetrics.size(
            for: item,
            historyStore: appState.historyStore,
            visible: visible,
            maxHeight: availableAbove
        )

        var x = midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        let height = min(size.height, availableAbove)
        let y = panelTop + bubbleGap
        return NSRect(x: x, y: y, width: size.width, height: height)
    }

    private func screenForBubble() -> NSScreen? {
        if let timeline = timelinePanelController?.panelFrame {
            return NSScreen.screens.first { $0.frame.intersects(timeline) } ?? NSScreen.main
        }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    // MARK: - Window plumbing

    private func presentBubble(_ content: ClipQuickPreview, frame: NSRect) {
        let hosting = NSHostingController(rootView: content)
        if let existing = previewWindow {
            if let current = existing.contentViewController as? NSHostingController<ClipQuickPreview> {
                current.rootView = content
            } else {
                existing.contentViewController = hosting
            }
            existing.setFrame(frame, display: true)
            applyBubbleChrome(to: existing)
            existing.orderFrontRegardless()
        } else {
            let panel = makeBubblePanel(size: frame.size)
            panel.contentViewController = hosting
            previewWindow = panel
            panel.setFrame(frame, display: true)
            applyBubbleChrome(to: panel)
            panel.orderFrontRegardless()
        }
    }

    /// Match the timeline panel: AppKit corner mask clears opaque rectangular "ears"
    /// outside the Liquid Glass silhouette.
    private func applyBubbleChrome(to panel: NSPanel) {
        PanelCornerMask.apply(to: panel.contentViewController?.view)
        PanelCornerMask.apply(to: panel.contentView)
    }

    private func presentEdit<Content: View>(_ content: Content, size: NSSize, title: String) {
        let hosting = NSHostingController(rootView: content)
        let alreadyVisible = editWindow?.isVisible == true
        let panel: NSPanel
        if let existing = editWindow {
            panel = existing
            if let current = panel.contentViewController as? NSHostingController<Content> {
                current.rootView = content
            } else {
                panel.contentViewController = hosting
            }
        } else {
            panel = makeEditPanel(size: size, title: title)
            panel.contentViewController = hosting
            editWindow = panel
        }

        panel.title = title
        if !alreadyVisible {
            panel.setContentSize(size)
            positionCentered(panel, size: size)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func makeBubblePanel(size: NSSize) -> NSPanel {
        let panel = PreviewBubblePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // False so text selection / image pan aren't stolen as window drags.
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.delegate = self
        panel.minSize = NSSize(width: 240, height: 140)
        panel.maxSize = NSSize(width: 900, height: 800)
        return panel
    }

    private func makeEditPanel(size: NSSize, title: String) -> NSPanel {
        let panel = DetachedClipPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.isOpaque = true
        panel.delegate = self
        panel.minSize = NSSize(width: 420, height: 280)
        return panel
    }

    private func positionCentered(_ panel: NSPanel, size: NSSize) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + 40
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === editWindow {
            sender.orderOut(nil)
            scheduleClearEditing()
            return false
        }
        if sender === previewWindow {
            sender.orderOut(nil)
            scheduleClearPreview()
            return false
        }
        return true
    }
}

enum PreviewBubbleMetrics {
    /// Adaptive bubble size from content. Height is capped by space above the timeline panel.
    static func size(
        for item: ClipItem,
        historyStore: HistoryStore,
        visible: NSRect,
        maxHeight: CGFloat
    ) -> NSSize {
        let maxW = min(560, max(320, visible.width * 0.48))
        let maxH = max(150, maxHeight)
        let minW: CGFloat = 260
        let minH: CGFloat = 150

        switch item.primaryType {
        case .image:
            if let pixels = item.storedImagePixelSize {
                let aspect = CGFloat(pixels.width) / max(1, CGFloat(pixels.height))
                var width = maxW
                var height = width / aspect
                if height > maxH - 44 {
                    height = maxH - 44
                    width = height * aspect
                }
                // Room for segmented Image/Text control.
                height = min(maxH, height + 44)
                return NSSize(
                    width: min(maxW, max(minW, width)),
                    height: min(maxH, max(minH + 40, height))
                )
            }
            return NSSize(width: maxW * 0.9, height: min(maxH, maxH * 0.85))

        case .url:
            return NSSize(width: min(maxW, 480), height: min(maxH, max(minH + 80, 420)))

        default:
            let text = item.previewText
            let lines = max(1, text.split(whereSeparator: \.isNewline).count)
            let chars = text.count
            // Short snippets get a compact bubble; long notes grow toward available height.
            let width: CGFloat
            if chars < 40 {
                width = min(maxW, max(minW, CGFloat(chars) * 9 + 80))
            } else if chars < 180 {
                width = min(maxW, 380)
            } else {
                width = maxW
            }
            let estimatedLines = max(lines, Int(ceil(Double(chars) / 42.0)))
            let height = min(maxH, max(minH, CGFloat(estimatedLines) * 22 + 56))
            return NSSize(width: width, height: height)
        }
    }
}

private class DetachedClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Bubble stays non-key until the user starts editing (click), so Space keeps
/// dismissing via the timeline panel shortcuts.
private final class PreviewBubblePanel: DetachedClipPanel {}
