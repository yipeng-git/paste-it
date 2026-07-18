import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    /// Live registration state from the system — the source of truth for UI.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
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
