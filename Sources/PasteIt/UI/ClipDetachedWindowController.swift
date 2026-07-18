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

    private let editSize = NSSize(width: 680, height: 520)
    private let previewSize = NSSize(width: 600, height: 420)

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func start() {
        // dropFirst skips the initial nil emission so we don't touch windows at launch.
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

    /// True when `window` is one of the detached edit/preview panels.
    func owns(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === editWindow || window === previewWindow
    }

    private func schedule(_ work: @escaping (ClipDetachedWindowController) -> Void) {
        // Break out of any in-flight @Published exclusivity / layout pass.
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

        // Editing and preview are mutually exclusive — clear preview without
        // nesting that write inside the editingClip Combine delivery.
        if appState.previewClip != nil, !isApplyingState {
            isApplyingState = true
            appState.previewClip = nil
            isApplyingState = false
        }

        let root = ClipEditView(item: item, historyStore: appState.historyStore) { [weak self] in
            self?.scheduleClearEditing()
        }
        present(root, in: &editWindow, size: editSize, title: "Edit Clip", makeKey: true)
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

    // MARK: - Preview

    private func syncPreviewWindow(with item: ClipItem?) {
        guard let item else {
            closePreviewWindow()
            return
        }
        if appState.editingClip != nil {
            // Don't steal from an active editor.
            if !isApplyingState {
                isApplyingState = true
                appState.previewClip = nil
                isApplyingState = false
            }
            return
        }

        let root = ClipQuickPreview(item: item, historyStore: appState.historyStore) { [weak self] in
            self?.scheduleClearPreview()
        }
        // Non-activating so the timeline keeps key focus for space / shortcuts.
        present(root, in: &previewWindow, size: previewSize, title: "Preview", makeKey: false)
    }

    private func closePreviewWindow() {
        guard let window = previewWindow, window.isVisible else { return }
        window.orderOut(nil)
    }

    private func scheduleClearPreview() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.appState.previewClip != nil else { return }
            self.isApplyingState = true
            self.appState.previewClip = nil
            self.isApplyingState = false
        }
    }

    // MARK: - Window plumbing

    private func present<Content: View>(
        _ content: Content,
        in windowSlot: inout NSPanel?,
        size: NSSize,
        title: String,
        makeKey: Bool
    ) {
        let hosting = NSHostingController(rootView: content)

        let alreadyVisible = windowSlot?.isVisible == true
        let panel: NSPanel
        if let existing = windowSlot {
            panel = existing
            // Updating rootView in place avoids tearing down the titlebar mid-layout.
            if let current = panel.contentViewController as? NSHostingController<Content> {
                current.rootView = content
            } else {
                panel.contentViewController = hosting
            }
        } else {
            panel = makePanel(size: size, title: title)
            panel.contentViewController = hosting
            windowSlot = panel
        }

        panel.title = title
        if !alreadyVisible {
            panel.setContentSize(size)
            positionCentered(panel, size: size)
        }
        panel.orderFrontRegardless()
        if makeKey {
            panel.makeKey()
        }
    }

    private func makePanel(size: NSSize, title: String) -> NSPanel {
        // Keep the chrome simple: titled + closable + resizable.
        // fullSizeContentView / transparent titlebar has been crashing in
        // NSTitlebarView layout under macOS 26 when hosting SwiftUI.
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
        // Hide instead of destroying so we don't race AppKit's titlebar teardown
        // against SwiftUI hosting cleanup. Clear AppState on the next turn.
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

private final class DetachedClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
