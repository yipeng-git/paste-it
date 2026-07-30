import Foundation
import Sparkle

/// Sparkle-backed updater. Keep `shared` alive for the app lifetime so automatic checks run.
@MainActor
final class UpdateChecker: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateChecker()

    private var updaterController: SPUStandardUpdaterController!
    /// Set before user-initiated checks so delegate callbacks know menu vs settings.
    private var pendingManualSource: String?
    /// Source for the in-flight update cycle (`auto` / `menu` / `settings`).
    private var cycleSource: String = "auto"

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Manual check from menu or Settings → About. Sparkle presents its own UI.
    func checkForUpdates(source: String = "menu") {
        pendingManualSource = source
        updaterController.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        switch updateCheck {
        case .updatesInBackground:
            cycleSource = "auto"
        case .updates, .updateInformation:
            cycleSource = pendingManualSource ?? "menu"
            pendingManualSource = nil
        @unknown default:
            cycleSource = pendingManualSource ?? "auto"
            pendingManualSource = nil
        }
        Analytics.updateInteraction(
            action: "check",
            source: cycleSource,
            fromVersion: currentVersion()
        )
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Analytics.updateInteraction(
            action: "found",
            source: cycleSource,
            fromVersion: currentVersion(),
            toVersion: item.displayVersionString
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        Analytics.updateInteraction(
            action: "not_found",
            source: cycleSource,
            fromVersion: currentVersion(),
            result: "no_update"
        )
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        Analytics.updateInteraction(
            action: "download",
            source: cycleSource,
            fromVersion: currentVersion(),
            toVersion: item.displayVersionString
        )
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Analytics.updateInteraction(
            action: "download",
            source: cycleSource,
            fromVersion: currentVersion(),
            toVersion: item.displayVersionString,
            result: "success"
        )
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        Analytics.updateInteraction(
            action: "fail",
            source: cycleSource,
            fromVersion: currentVersion(),
            toVersion: item.displayVersionString,
            result: "download_failed"
        )
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        Analytics.updateInteraction(
            action: "dismiss",
            source: cycleSource,
            fromVersion: currentVersion(),
            result: "download_cancelled"
        )
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let action: String
        let result: String
        switch choice {
        case .install:
            action = "install"
            result = "accepted"
        case .dismiss:
            action = "dismiss"
            result = "dismissed"
        case .skip:
            action = "dismiss"
            result = "skipped"
        @unknown default:
            action = "dismiss"
            result = "unknown"
        }
        Analytics.updateInteraction(
            action: action,
            source: cycleSource,
            fromVersion: currentVersion(),
            toVersion: updateItem.displayVersionString,
            result: result
        )
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Analytics.updateInteraction(
            action: "install",
            source: cycleSource,
            fromVersion: currentVersion(),
            toVersion: item.displayVersionString,
            result: "installing"
        )
    }

    func updater(
        _ updater: SPUUpdater,
        didAbortWithError error: Error
    ) {
        Analytics.updateInteraction(
            action: "fail",
            source: cycleSource,
            fromVersion: currentVersion(),
            result: "aborted"
        )
    }

    // MARK: - Private

    private func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
