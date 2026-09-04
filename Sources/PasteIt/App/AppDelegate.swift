import AppKit
import PasteItCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.bundle = Bundle.module
        // Tahoe injects gear/etc. on Preferences/Settings; opt out before any menu opens.
        MenuIconPolicy.disableSystemInjectedIcons()
        NSApp.setActivationPolicy(.accessory)
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.stop()
    }
}
