import SwiftUI

@main
@MainActor
struct PasteItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let runtime = AppRuntime.shared

    var body: some Scene {
        Settings {
            SettingsView(appState: runtime.state)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}
