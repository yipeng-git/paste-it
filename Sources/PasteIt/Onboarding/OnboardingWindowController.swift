import AppKit
import SwiftUI

/// First-launch tutorial window. Mirrors `SettingsWindowController` activation policy handling.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var wasAccessory = true
    private var settings: AppSettings?
    private var analytics: OnboardingAnalyticsHandle?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(settings: AppSettings, source: String = "settings") {
        self.settings = settings
        let session = OnboardingAnalyticsHandle(source: source)
        self.analytics = session
        wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory {
            NSApp.setActivationPolicy(.regular)
        }

        if let existing = window {
            // Recreate content so the carousel always starts at page 1.
            existing.contentViewController = makeHostingController(settings: settings, analytics: session)
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            existing.center()
            return
        }

        let window = makeWindow(settings: settings, analytics: session)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    func close() {
        window?.close()
    }

    private func makeWindow(settings: AppSettings, analytics: OnboardingAnalyticsHandle) -> NSWindow {
        let hosting = makeHostingController(settings: settings, analytics: analytics)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Paste It"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 640, height: 420))
        window.minSize = NSSize(width: 640, height: 420)
        window.maxSize = NSSize(width: 640, height: 420)
        return window
    }

    private func makeHostingController(
        settings: AppSettings,
        analytics: OnboardingAnalyticsHandle
    ) -> NSHostingController<OnboardingView> {
        let root = OnboardingView(settings: settings, analytics: analytics) { [weak self] in
            self?.close()
        }
        return NSHostingController(rootView: root)
    }

    func windowWillClose(_ notification: Notification) {
        analytics?.markDismissedIfNeeded()
        analytics = nil
        if let settings, !settings.hasCompletedOnboarding {
            settings.hasCompletedOnboarding = true
        }
        guard wasAccessory else { return }
        // Keep regular policy if Settings (or another regular window) is still open.
        if SettingsWindowController.shared.isVisible { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
