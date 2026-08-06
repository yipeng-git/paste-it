import AppKit
import SwiftUI

/// Install / What's New tutorial window. Mirrors `SettingsWindowController` activation policy handling.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var wasAccessory = true
    private var settings: AppSettings?
    private var flow: OnboardingFlow = .install
    private var analytics: OnboardingAnalyticsHandle?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(
        settings: AppSettings,
        flow: OnboardingFlow,
        source: String
    ) {
        self.settings = settings
        self.flow = flow
        let session = OnboardingAnalyticsHandle(source: source)
        self.analytics = session
        wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory {
            NSApp.setActivationPolicy(.regular)
        }

        let title = "Paste It"
        if let existing = window {
            existing.title = title
            existing.setContentSize(NSSize(width: 640, height: 500))
            existing.minSize = NSSize(width: 640, height: 500)
            existing.maxSize = NSSize(width: 640, height: 500)
            existing.contentViewController = makeHostingController(
                settings: settings,
                flow: flow,
                analytics: session
            )
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            existing.center()
            return
        }

        let window = makeWindow(settings: settings, flow: flow, analytics: session)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    func close() {
        window?.close()
    }

    private func makeWindow(
        settings: AppSettings,
        flow: OnboardingFlow,
        analytics: OnboardingAnalyticsHandle
    ) -> NSWindow {
        let hosting = makeHostingController(settings: settings, flow: flow, analytics: analytics)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
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
        window.setContentSize(NSSize(width: 640, height: 500))
        window.minSize = NSSize(width: 640, height: 500)
        window.maxSize = NSSize(width: 640, height: 500)
        return window
    }

    private func makeHostingController(
        settings: AppSettings,
        flow: OnboardingFlow,
        analytics: OnboardingAnalyticsHandle
    ) -> NSHostingController<OnboardingView> {
        let root = OnboardingView(
            settings: settings,
            flow: flow,
            analytics: analytics
        ) { [weak self] in
            self?.close()
        }
        return NSHostingController(rootView: root)
    }

    func windowWillClose(_ notification: Notification) {
        analytics?.markDismissedIfNeeded()
        analytics = nil
        if let settings {
            switch flow {
            case .install:
                if !settings.hasCompletedOnboarding {
                    settings.hasCompletedOnboarding = true
                }
                settings.seenWhatsNewContentVersion = AppSettings.currentWhatsNewContentVersion
            case .update:
                settings.seenWhatsNewContentVersion = AppSettings.currentWhatsNewContentVersion
            }
        }
        guard wasAccessory else { return }
        if SettingsWindowController.shared.isVisible { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
