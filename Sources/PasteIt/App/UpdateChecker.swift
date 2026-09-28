import Foundation
import Combine
import PasteItCore
import Sparkle

/// Sparkle-backed updater. Keep `shared` alive for the app lifetime so automatic checks run.
@MainActor
final class UpdateChecker: NSObject, ObservableObject, SPUUpdaterDelegate, @MainActor SPUStandardUserDriverDelegate {
    static let shared = UpdateChecker()

    private var updaterController: SPUStandardUpdaterController!
    /// Also distinguishes automatic install prompts from menu/settings checks.
    private var pendingCheckSource: String?
    /// Source for the in-flight update cycle (`auto` / `menu` / `settings`).
    private var cycleSource: String = "auto"
    private var promptState = AutomaticUpdatePromptState()
    private var observations = Set<AnyCancellable>()

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        observeUpdaterSettings()
    }

    /// Manual check from menu or Settings → About. Sparkle presents its own UI.
    func checkForUpdates(source: String = "menu") {
        guard canCheckForUpdates else { return }
        // Bringing an existing alert forward doesn't start a cycle or invoke
        // mayPerform. Don't leave its source pending for an unrelated check.
        if !updaterController.updater.sessionInProgress {
            pendingCheckSource = source
        }
        updaterController.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    // MARK: - Immediate update reminders

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Take responsibility for bringing scheduled alerts to the front even
        // though this is a dockless app. No interaction or Paste Stack gating.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Critical updates can reach this callback without finishing the
        // background cycle first. Clear the pending handoff to avoid a loop.
        promptState.updatePresented()
        if !handleShowingUpdate {
            // Sparkle defers this callback until its alert can be brought into
            // focus. This reuses the existing session rather than checking again.
            updaterController.checkForUpdates(nil)
        }
        Analytics.updateInteraction(
            action: "shown",
            source: cycleSource,
            fromVersion: currentVersion(),
            toVersion: update.displayVersionString,
            result: state.stage == .installing ? "ready_to_install" : "update_available"
        )
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        promptState.updatePrepared()
        // Let Sparkle finish the automatic cycle and keep its installer alive.
        // Holding the installation block would stall all subsequent checks.
        return false
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard promptState.finishCycle(failed: error != nil) else { return }
        // Sparkle has cleared sessionInProgress before invoking this delegate.
        // Start synchronously: deferring would race its next scheduling probe.
        // Its installer is already prepared, so the standard UI offers restart
        // immediately, along with install-on-quit and skip-version choices.
        checkForUpdates(source: "auto")
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        switch updateCheck {
        case .updatesInBackground:
            cycleSource = "auto"
        case .updates, .updateInformation:
            cycleSource = pendingCheckSource ?? "menu"
            pendingCheckSource = nil
        @unknown default:
            cycleSource = pendingCheckSource ?? "auto"
            pendingCheckSource = nil
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

    private func observeUpdaterSettings() {
        let updater = updaterController.updater
        Publishers.Merge3(
            updater.publisher(for: \.canCheckForUpdates),
            updater.publisher(for: \.automaticallyChecksForUpdates),
            updater.publisher(for: \.automaticallyDownloadsUpdates)
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
        .store(in: &observations)
    }
}
