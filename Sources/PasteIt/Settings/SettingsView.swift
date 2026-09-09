import SwiftUI
import PasteItCore

struct SettingsView: View {
    // System Settings on macOS 26: 215 pt of glass plus the 8 pt leading inset.
    static let sidebarWidth: CGFloat = 223

    private enum Page: Hashable {
        case general, clipboard, stack, folders, privacy, storage, about

        var title: String {
            switch self {
            case .general: L10n.tr("settings.tab.general", default: "General")
            case .clipboard: L10n.tr("settings.tab.clipboard", default: "Clipboard & History")
            case .stack: L10n.tr("settings.tab.stack", default: "Stack")
            case .folders: L10n.tr("settings.tab.folders", default: "Folders")
            case .privacy: L10n.tr("settings.tab.privacy", default: "Privacy")
            case .storage: L10n.tr("settings.tab.storage", default: "Storage")
            case .about: L10n.tr("settings.tab.about", default: "About")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .clipboard: "clipboard.fill"
            case .stack: "square.3.layers.3d"
            case .folders: "folder.fill"
            case .privacy: "hand.raised.fill"
            case .storage: "internaldrive.fill"
            case .about: "info"
            }
        }

        var sidebarTitle: String {
            self == .clipboard
                ? L10n.tr("settings.sidebar.clipboard", default: "Clipboard")
                : title
        }

        var tint: Color {
            switch self {
            case .general, .storage: .gray
            case .clipboard, .privacy, .about: .blue
            case .stack: .indigo
            case .folders: .orange
            }
        }
    }

    @ObservedObject var appState: AppState
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var historyStore: HistoryStore
    /// Mirrors SMAppService registration; refreshed on appear and app activation
    /// so turning the login item off in System Settings is reflected here.
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    @State private var updateStatus: String?
    @State private var pendingCleanup: PendingCleanup?
    @State private var selectedPage: Page? = .general
    @State private var accessibilityTrusted = SystemPasteSynthesizer.isAccessibilityTrusted

    private struct PendingCleanup: Identifiable {
        let id = UUID()
        let ids: Set<UUID>
        let keepSaved: Bool
        let retention: AppSettings.KeepHistory?
    }

    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.settings)
        _historyStore = ObservedObject(wrappedValue: appState.historyStore)
    }

    var body: some View {
        // Standard navigation owns the Liquid Glass sidebar and toolbar on macOS 26.
        // Keep Form content on its system surface instead of layering glass over text.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selectedPage) {
                Section {
                    navigationRow(.general)
                    navigationRow(.clipboard)
                    navigationRow(.stack)
                    navigationRow(.folders)
                }
                Section {
                    navigationRow(.privacy)
                    navigationRow(.storage)
                }
                Section {
                    navigationRow(.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: Self.sidebarWidth,
                ideal: Self.sidebarWidth,
                max: Self.sidebarWidth
            )
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle((selectedPage ?? .general).title)
        }
        .navigationSplitViewStyle(.balanced)
        .toggleStyle(.switch)
        .frame(minWidth: 760, minHeight: 580)
        .onAppear {
            accessibilityTrusted = SystemPasteSynthesizer.isAccessibilityTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = SystemPasteSynthesizer.isAccessibilityTrusted
        }
        .sheet(item: $pendingCleanup) { cleanup in
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("removal.confirmTitle", default: "Review History Cleanup"))
                    .font(.headline)
                Text(L10n.tr("removal.confirmCount", default: "%lld clips will be permanently deleted. This cannot be undone and ends removal undo.", cleanup.ids.count))
                    .fixedSize(horizontal: false, vertical: true)
                Text(cleanup.keepSaved
                    ? L10n.tr("removal.keepSaved", default: "Pinned clips and clips in folders will be kept.")
                    : L10n.tr("removal.includeSaved", default: "This includes Pinned and every folder. The folders themselves will remain."))
                    .foregroundStyle(.secondary)
                if let retention = cleanup.retention {
                    Text(L10n.tr("removal.newRetention", default: "New retention period: %@", retention.title))
                }
                HStack {
                    Spacer()
                    Button(L10n.tr("common.cancel", default: "Cancel"), role: .cancel) { pendingCleanup = nil }
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.tr("removal.confirmDelete", default: "Delete Reviewed Clips"), role: .destructive) {
                        if historyStore.deleteReviewedClips(ids: cleanup.ids, keepSaved: cleanup.keepSaved),
                           let retention = cleanup.retention {
                            settings.keepHistory = retention
                        }
                        pendingCleanup = nil
                    }
                }
            }
            .padding(24)
            .frame(width: 440)
        }
        .alert(L10n.tr("removal.failedTitle", default: "History Was Not Changed"), isPresented: Binding(
            get: { historyStore.removalError != nil },
            set: { if !$0 { historyStore.removalError = nil } }
        )) {
            Button(L10n.tr("action.dismiss", default: "Dismiss message")) { historyStore.removalError = nil }
        } message: {
            Text(historyStore.removalError ?? "")
        }
    }

    private func navigationRow(_ page: Page) -> some View {
        NavigationLink(value: page) {
            Label {
                Text(page.sidebarTitle)
                    .font(.system(size: 13))
                    .lineLimit(2)
            } icon: {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(page.tint.gradient, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedPage ?? .general {
        case .general: general
        case .clipboard: clipboard
        case .stack: stack
        case .folders: FoldersSettingsView(historyStore: historyStore)
        case .privacy: PrivacySettingsView(settings: settings)
        case .storage: storage
        case .about: about
        }
    }

    private var versionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return L10n.tr("settings.version", default: "Paste It %@ (%@)", short, build)
    }

    private var about: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paste It")
                            .font(.title2.bold())
                        Text(versionLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                Text(L10n.tr("settings.aboutBlurb", default: "Paste It is a local-first clipboard manager. History stays on this Mac."))
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.group.help", default: "Help")) {
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

            Section(L10n.tr("settings.group.updates", default: "Updates")) {
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
        .pasteItGlassButtonStyle()
    }

    private var general: some View {
        Form {
            Section(L10n.tr("settings.group.startup", default: "Startup")) {
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
            }

            Section {
                Picker(L10n.tr("action.setting", default: "Timeline primary action"), selection: Binding(
                    get: { settings.timelinePrimaryAction },
                    set: { settings.timelinePrimaryAction = $0 }
                )) {
                    ForEach(TimelinePrimaryAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                Toggle(L10n.tr("settings.pastePlainDefault", default: "Paste as plain text by default"), isOn: $settings.pasteAsPlainTextByDefault)
                if settings.timelinePrimaryAction == .paste && !accessibilityTrusted {
                    DirectPastePermissionView()
                }
            } header: {
                Text(L10n.tr("settings.group.pasting", default: "Pasting"))
            } footer: {
                Text(L10n.tr("action.settingDetail", default: "Double-click, Return, and ⌘1–9 use the selected action. Direct Paste is the default. ⇧Return always pastes plain text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                shortcutRow(L10n.tr("menu.openPaste", default: "Open Paste"), keys: "⇧⌘V")
                shortcutRow(L10n.tr("stack.open", default: "Open Paste Stack"), keys: "⇧⌘C")
                shortcutRow(L10n.tr("menu.pastePlain", default: "Paste Without Formatting"), keys: "⌃⌘V")
            } header: {
                Text(L10n.tr("settings.group.shortcuts", default: "Keyboard Shortcuts"))
            } footer: {
                Text(L10n.tr("settings.plainTextFootnote", default: "⌃⌘V pastes once as plain text, then restores the original clipboard (Accessibility required to auto-paste). In the timeline, ⇧↩ pastes the selection as plain text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, keys: String) -> some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel(keys)
        }
    }

    private var clipboard: some View {
        Form {
            Section(L10n.tr("settings.group.capture", default: "Capture")) {
                Toggle(L10n.tr("settings.pauseCapture", default: "Pause clipboard capture"), isOn: $settings.capturePaused)
            }

            Section {
                Picker(L10n.tr("settings.keepHistory", default: "Keep history"), selection: Binding(
                    get: { settings.keepHistory },
                    set: { retention in
                        let ids = Set(historyStore.retentionCandidates(retention).map(\.id))
                        if ids.isEmpty { settings.keepHistory = retention }
                        else { pendingCleanup = PendingCleanup(ids: ids, keepSaved: true, retention: retention) }
                    }
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
            } header: {
                Text(L10n.tr("settings.group.history", default: "History"))
            } footer: {
                Text(L10n.tr("removal.keepSaved", default: "Pinned clips and clips in folders will be kept."))
            }

            Section {
                DisclosureGroup(L10n.tr("settings.group.advanced", default: "Advanced")) {
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
            }
        }
        .formStyle(.grouped)
    }

    private var stack: some View {
        Form {
            Section {
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
            } footer: {
                Text(L10n.tr("settings.stackFootnote", default: "⇧⌘C opens or closes Paste Stack. While the stack has items, ⌘V in any app pastes the next one (Accessibility required). Runtime controls live in the Stack panel and the ⋯ menu."))
            }

            Section(L10n.tr("settings.group.shortcuts", default: "Keyboard Shortcuts")) {
                shortcutRow(L10n.tr("stack.open", default: "Open Paste Stack"), keys: "⇧⌘C")
            }
        }
        .formStyle(.grouped)
    }

    private var storage: some View {
        Form {
            Section(L10n.tr("settings.tab.storage", default: "Storage")) {
                Stepper(
                    L10n.tr("settings.maxBinaryStorage", default: "Max binary storage: %lld MB", settings.maxBlobMegabytes),
                    value: $settings.maxBlobMegabytes,
                    in: 128...20_480,
                    step: 128
                )

                Button(L10n.tr("settings.pruneNow", default: "Prune Now")) {
                    pendingCleanup = PendingCleanup(ids: Set(historyStore.pruneCandidates().map(\.id)), keepSaved: true, retention: nil)
                }
            }

            Section(L10n.tr("settings.group.cleanup", default: "History Cleanup")) {
                Button(L10n.tr("removal.clearKeepSaved", default: "Clear History, Keep Pinned & Folders…"), role: .destructive) {
                    pendingCleanup = PendingCleanup(ids: Set(historyStore.clearHistoryCandidates(keepSaved: true).map(\.id)), keepSaved: true, retention: nil)
                }

                Button(L10n.tr("settings.clearAllHistory", default: "Clear All History"), role: .destructive) {
                    pendingCleanup = PendingCleanup(ids: Set(historyStore.clips.map(\.id)), keepSaved: false, retention: nil)
                }
            }
        }
        .formStyle(.grouped)
    }
}
