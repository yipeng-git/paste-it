import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    /// Live registration state from the system — the source of truth for UI.
    static var isEnabled: Bool {
        guard supportsLaunchAtLogin else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Login-item registration is only safe for a real `.app` bundle that is
    /// not a local SPM/dev build. Bare `.build/.../PasteIt` executables get a
    /// new ad-hoc CDHash on every rebuild; `SMAppService.mainApp.register()`
    /// then accumulates duplicate login items, and macOS launches each one in
    /// Terminal at login.
    static var supportsLaunchAtLogin: Bool {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension.lowercased() == "app" else { return false }
        let path = bundleURL.standardizedFileURL.path
        if path.contains("/.build/") { return false }
        return true
    }

    static func setEnabled(_ enabled: Bool) {
        guard supportsLaunchAtLogin else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login update failed: \(error.localizedDescription)")
        }
    }

    /// Aligns the actual SMAppService registration with the stored setting at
    /// startup. Needed because the setting defaults to on — without this,
    /// existing installs would show the toggle enabled but never register.
    /// `.requiresApproval` means the user turned it off in System Settings;
    /// respect that and don't re-register.
    static func syncAtStartup(enabled: Bool) {
        guard supportsLaunchAtLogin else { return }
        let status = SMAppService.mainApp.status
        if enabled {
            guard status == .notRegistered || status == .notFound else { return }
            setEnabled(true)
        } else {
            guard status == .enabled else { return }
            setEnabled(false)
        }
    }
}
