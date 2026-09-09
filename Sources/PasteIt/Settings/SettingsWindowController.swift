import AppKit
import SwiftUI
import PasteItCore

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
    }

    private func makeWindow(appState: AppState) -> NSWindow {
        let root = SettingsView(appState: appState)
        let hosting = SettingsHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("settings.windowTitle", default: "Paste It Settings")
        // Keep a real titlebar toolbar even though settings has no sidebar toggle.
        // Without it, the full-height system sidebar starts below the titlebar.
        let toolbar = NSToolbar(identifier: "PasteItSettingsToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 760, height: 580)
        window.center()
        window.setFrameAutosaveName("PasteItSettings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard wasAccessory else { return }
        if OnboardingWindowController.shared.isVisible { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Removing SwiftUI's toggle alone still allows AppKit to collapse a sidebar by
/// dragging its divider. Configure the native split item without replacing its
/// delegate or the system's Liquid Glass presentation.
@MainActor
private final class SettingsHostingController: NSHostingController<SettingsView> {
    override func viewDidLayout() {
        super.viewDidLayout()
        keepSidebarVisible(in: self)
    }

    private func keepSidebarVisible(in controller: NSViewController) {
        if let split = controller as? NSSplitViewController {
            for item in split.splitViewItems where item.behavior == .sidebar {
                if !item.allowsFullHeightLayout { item.allowsFullHeightLayout = true }
                if item.minimumThickness != SettingsView.sidebarWidth {
                    item.minimumThickness = SettingsView.sidebarWidth
                }
                if item.maximumThickness != SettingsView.sidebarWidth {
                    item.maximumThickness = SettingsView.sidebarWidth
                }
                if item.canCollapse { item.canCollapse = false }
                if item.canCollapseFromWindowResize { item.canCollapseFromWindowResize = false }
                if item.isCollapsed { item.isCollapsed = false }
            }
        }
        for child in controller.children {
            keepSidebarVisible(in: child)
        }
    }
}
