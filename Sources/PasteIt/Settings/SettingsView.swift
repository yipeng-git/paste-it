import SwiftUI
import PasteItCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var historyStore: HistoryStore
    /// Mirrors SMAppService registration; refreshed on appear and app activation
    /// so turning the login item off in System Settings is reflected here.
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    @State private var updateStatus: String?

    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.settings)
        _historyStore = ObservedObject(wrappedValue: appState.historyStore)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                about
                    .tabItem { Label(L10n.tr("settings.tab.about", default: "About"), systemImage: "info.circle") }
                    .tag(0)

                general
                    .tabItem { Label(L10n.tr("settings.tab.general", default: "General"), systemImage: "gearshape") }
                    .tag(1)

                PrivacySettingsView(settings: settings)
                    .tabItem { Label(L10n.tr("settings.tab.privacy", default: "Privacy"), systemImage: "hand.raised") }
                    .tag(2)

                FoldersSettingsView(historyStore: historyStore)
                    .tabItem { Label(L10n.tr("settings.tab.folders", default: "Folders"), systemImage: "folder") }
                    .tag(3)

                stack
                    .tabItem { Label(L10n.tr("settings.tab.stack", default: "Stack"), systemImage: "tray.full") }
                    .tag(4)

                storage
                    .tabItem { Label(L10n.tr("settings.tab.storage", default: "Storage"), systemImage: "internaldrive") }
                    .tag(5)
            }

            versionFooter
        }
    }

    private var versionFooter: some View {
        Text(versionLabel)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .help(Text(versionLabel))
    }

    private var versionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return L10n.tr("settings.version", default: "Paste It %@ (%@)", short, build)
    }

    private var about: some View {
        Form {
            Section {
                Text(L10n.tr("settings.aboutBlurb", default: "Paste It is a local-first clipboard manager. History stays on this Mac."))
                    .foregroundStyle(.secondary)
                LabeledContent(L10n.tr("settings.versionLabel", default: "Version"), value: versionLabel)
            }

            Section {
                Button(L10n.tr("settings.showTutorial", default: "Show Tutorial…")) {
                    OnboardingWindowController.shared.show(
                        settings: settings,
                        flow: .install,
                        source: "settings"
                    )
                }
                Button(L10n.tr("settings.whatsNew", default: "What's New…")) {
                    OnboardingWindowController.shared.show(
                        settings: settings,
                        flow: .update,
                        source: "settings"
                    )
                }
            }

            Section {
                Button(L10n.tr("menu.checkUpdates", default: "Check for Updates…")) {
                    UpdateChecker.shared.checkForUpdates(source: "settings")
                    updateStatus = L10n.tr("settings.checkingUpdates", default: "Checking for updates…")
                }
                .disabled(!UpdateChecker.shared.canCheckForUpdates)
                if let updateStatus {
                    Text(updateStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var general: some View {
        Form {
            Toggle(L10n.tr("settings.pauseCapture", default: "Pause clipboard capture"), isOn: $settings.capturePaused)
            Toggle(L10n.tr("settings.pastePlainDefault", default: "Paste as plain text by default"), isOn: $settings.pasteAsPlainTextByDefault)
            Text(L10n.tr("settings.plainTextFootnote", default: "⌃⌘V pastes once as plain text, then restores the original clipboard (Accessibility required to auto-paste). In the timeline, ⇧↩ pastes the selection as plain text."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(L10n.tr("settings.launchAtLogin", default: "Launch at login"), isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { enabled in
                    LaunchAtLoginManager.setEnabled(enabled)
                    settings.launchAtLogin = enabled
                    // Read back: registration can stay pending (.requiresApproval)
                    // when the user previously disabled it in System Settings.
                    launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
                }
            ))
            .disabled(!LaunchAtLoginManager.supportsLaunchAtLogin)
            .onAppear {
                launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
            }

            Picker(L10n.tr("settings.keepHistory", default: "Keep history"), selection: Binding(
                get: { settings.keepHistory },
                set: { settings.keepHistory = $0; historyStore.pruneHistory() }
            )) {
                ForEach(AppSettings.KeepHistory.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            LabeledContent(L10n.tr("settings.maxHistoryItems", default: "Max history items")) {
                HStack(spacing: 6) {
                    TextField(
                        "",
                        value: $settings.maxHistoryItems,
                        format: .number
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.maxHistoryItems) { _, newValue in
                        settings.maxHistoryItems = min(50_000, max(100, newValue))
                    }

                    Stepper(
                        "",
                        value: $settings.maxHistoryItems,
                        in: 100...50_000,
                        step: 100
                    )
                    .labelsHidden()
                }
            }

            LabeledContent(L10n.tr("settings.clipboardPolling", default: "Clipboard polling")) {
                HStack(spacing: 6) {
                    TextField(
                        "",
                        value: Binding(
                            get: { settings.clipboardCheckInterval },
                            set: {
                                settings.clipboardCheckInterval = min(
                                    2.0,
                                    max(0.2, ($0 * 20).rounded() / 20)
                                )
                            }
                        ),
                        format: .number.precision(.fractionLength(2))
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .textFieldStyle(.roundedBorder)

                    Text(L10n.tr("settings.seconds", default: "s"))
                        .foregroundStyle(.secondary)

                    Stepper(
                        "",
                        value: $settings.clipboardCheckInterval,
                        in: 0.2...2.0,
                        step: 0.05
                    )
                    .labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var stack: some View {
        Form {
            Picker(L10n.tr("settings.stackDirection", default: "Default paste direction"), selection: Binding(
                get: { settings.pasteStackDefaultDirection },
                set: { newValue in
                    settings.pasteStackDefaultDirection = newValue
                    appState.pasteStackController?.direction = newValue
                }
            )) {
                ForEach(PasteStackController.Direction.allCases) { direction in
                    Text(direction.title).tag(direction)
                }
            }

            Text(L10n.tr("settings.stackFootnote", default: "⇧⌘C opens or closes Paste Stack. While the stack has items, ⌘V in any app pastes the next one (Accessibility required). Runtime controls live in the Stack panel and the ⋯ menu."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var storage: some View {
        Form {
            Stepper(
                L10n.tr("settings.maxBinaryStorage", default: "Max binary storage: %lld MB", settings.maxBlobMegabytes),
                value: $settings.maxBlobMegabytes,
                in: 128...20_480,
                step: 128
            )

            Button(L10n.tr("settings.pruneNow", default: "Prune Now")) {
                historyStore.pruneHistory()
            }

            Button(L10n.tr("settings.clearKeepPinned", default: "Clear History, Keep Pinned"), role: .destructive) {
                historyStore.clearHistory(keepPinned: true)
            }

            Button(L10n.tr("settings.clearAllHistory", default: "Clear All History"), role: .destructive) {
                historyStore.clearHistory(keepPinned: false)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
