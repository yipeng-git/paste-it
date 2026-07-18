import Foundation
import Sparkle

/// Sparkle-backed updater. Keep `shared` alive for the app lifetime so automatic checks run.
@MainActor
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    private let updaterController: SPUStandardUpdaterController

    private override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Manual check from Settings → About. Sparkle presents its own UI.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}
