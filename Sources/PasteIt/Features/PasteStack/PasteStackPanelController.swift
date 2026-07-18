import AppKit
import QuartzCore
import SwiftUI

/// Floating Paste Stack panel — horizontal card strip, Paste-style.
@MainActor
final class PasteStackPanelController: NSObject, NSWindowDelegate {
    private let stack: PasteStackController
    private let historyStore: HistoryStore
    private var panel: NSPanel?
    private var isAnimating = false
    private var itemsObservation: NSKeyValueObservation?

    private let panelHeight: CGFloat = 280
    private let bottomInset: CGFloat = 56

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
            panel.setFrame(finalFrame, display: true)
            panel.orderFrontRegardless()
            return
        }

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
        panel.orderFrontRegardless()

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.isAnimating = false }
        })
    }

    func hide() {
        guard let panel, panel.isVisible, !isAnimating else { return }
        isAnimating = true
        let endFrame: NSRect
        if let screen = panel.screen ?? screenForCurrentFocus() {
            endFrame = panelSlideOffscreenFrame(from: panel.frame, screen: screen)
        } else {
            var fallback = panel.frame
            fallback.origin.y -= fallback.height
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

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(
            rootView: PasteStackView(stack: stack, historyStore: historyStore)
        )
        let panel = PasteStackFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
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
        panel.contentViewController = hosting
        panel.delegate = self
        return panel
    }

    private func targetFrame(for panel: NSPanel) -> NSRect {
        guard let screen = screenForCurrentFocus() else {
            return panel.frame
        }
        let visible = screen.visibleFrame
        let width = min(960, max(560, visible.width - 48))
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.minY + bottomInset,
            width: width,
            height: panelHeight
        )
    }

    private func screenForCurrentFocus() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stack.close()
        return false
    }
}

private final class PasteStackFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
