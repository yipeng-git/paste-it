import AppKit
import SwiftUI

/// Menu-bar (LSUIElement) apps often get a blank SwiftUI `Settings` scene.
/// Host preferences in an explicit `NSWindow` instead.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var wasAccessory = true

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(appState: AppState) {
        wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory {
            NSApp.setActivationPolicy(.regular)
        }

        let window = self.window ?? makeWindow(appState: appState)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    private func makeWindow(appState: AppState) -> NSWindow {
        let root = SettingsView(appState: appState)
            .frame(minWidth: 560, minHeight: 420)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Paste It Settings"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 640, height: 480))
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard wasAccessory else { return }
        if OnboardingWindowController.shared.isVisible { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
