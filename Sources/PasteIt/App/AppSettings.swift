import Foundation
import PasteItCore
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("timelinePrimaryAction") private var timelinePrimaryActionRaw = ""

    var timelinePrimaryAction: TimelinePrimaryAction {
        get { .initialValue(saved: timelinePrimaryActionRaw) }
        set {
            objectWillChange.send()
            timelinePrimaryActionRaw = newValue.rawValue
        }
    }

    func migratePrimaryAction() {
        timelinePrimaryAction = .initialValue(saved: timelinePrimaryActionRaw)
    }

    enum KeepHistory: String, CaseIterable, Identifiable {
        case oneDay
        case oneWeek
        case oneMonth
        case forever

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oneDay: return L10n.tr("keepHistory.oneDay", default: "1 Day")
            case .oneWeek: return L10n.tr("keepHistory.oneWeek", default: "1 Week")
            case .oneMonth: return L10n.tr("keepHistory.oneMonth", default: "1 Month")
            case .forever: return L10n.tr("keepHistory.forever", default: "Forever")
            }
        }

        var cutoffDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .oneDay: return calendar.date(byAdding: .day, value: -1, to: Date())
            case .oneWeek: return calendar.date(byAdding: .day, value: -7, to: Date())
            case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: Date())
            case .forever: return nil
            }
        }
    }

    @AppStorage("clipboardCheckInterval") var clipboardCheckInterval: Double = 0.35
    @AppStorage("capturePaused") var capturePaused: Bool = false
    @AppStorage("keepHistory") private var keepHistoryRaw: String = KeepHistory.forever.rawValue
    @AppStorage("maxHistoryItems") var maxHistoryItems: Int = 5000
    @AppStorage("maxBlobMegabytes") var maxBlobMegabytes: Int = 1024
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = true
    @AppStorage("pasteAsPlainTextByDefault") var pasteAsPlainTextByDefault: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    /// Bump when shipping a What's New feature pack (not every semver).
    static let currentWhatsNewContentVersion = 3
    @AppStorage("seenWhatsNewContentVersion") var seenWhatsNewContentVersion: Int = 0
    @AppStorage("agentAPIEnabled") var agentAPIEnabled: Bool = false
    /// Anonymous usage analytics (PostHog). Never includes clipboard contents.
    @AppStorage("analyticsEnabled") var analyticsEnabled: Bool = true
    @AppStorage("pasteStackDefaultDirection") private var pasteStackDefaultDirectionRaw: String =
        PasteStackController.Direction.oldestFirst.rawValue
    @AppStorage("ignoredBundleIdentifiers") private var ignoredBundleIdentifiersRaw: String = defaultIgnoredApps.joined(separator: "\n")
    @AppStorage("ignoredPasteboardTypes") private var ignoredPasteboardTypesRaw: String = defaultIgnoredTypes.joined(separator: "\n")

    /// Injectable preferences keep integration tests out of the user's defaults domain.
    init(defaults: UserDefaults = .standard) {
        _timelinePrimaryActionRaw = AppStorage(wrappedValue: "", "timelinePrimaryAction", store: defaults)
        _clipboardCheckInterval = AppStorage(wrappedValue: 0.35, "clipboardCheckInterval", store: defaults)
        _capturePaused = AppStorage(wrappedValue: false, "capturePaused", store: defaults)
        _keepHistoryRaw = AppStorage(wrappedValue: KeepHistory.forever.rawValue, "keepHistory", store: defaults)
        _maxHistoryItems = AppStorage(wrappedValue: 5000, "maxHistoryItems", store: defaults)
        _maxBlobMegabytes = AppStorage(wrappedValue: 1024, "maxBlobMegabytes", store: defaults)
        _launchAtLogin = AppStorage(wrappedValue: true, "launchAtLogin", store: defaults)
        _pasteAsPlainTextByDefault = AppStorage(wrappedValue: false, "pasteAsPlainTextByDefault", store: defaults)
        _hasCompletedOnboarding = AppStorage(wrappedValue: false, "hasCompletedOnboarding", store: defaults)
        _seenWhatsNewContentVersion = AppStorage(wrappedValue: 0, "seenWhatsNewContentVersion", store: defaults)
        _agentAPIEnabled = AppStorage(wrappedValue: false, "agentAPIEnabled", store: defaults)
        _analyticsEnabled = AppStorage(wrappedValue: true, "analyticsEnabled", store: defaults)
        _pasteStackDefaultDirectionRaw = AppStorage(wrappedValue: PasteStackController.Direction.oldestFirst.rawValue, "pasteStackDefaultDirection", store: defaults)
        _ignoredBundleIdentifiersRaw = AppStorage(wrappedValue: defaultIgnoredApps.joined(separator: "\n"), "ignoredBundleIdentifiers", store: defaults)
        _ignoredPasteboardTypesRaw = AppStorage(wrappedValue: defaultIgnoredTypes.joined(separator: "\n"), "ignoredPasteboardTypes", store: defaults)
    }

    var keepHistory: KeepHistory {
        get { KeepHistory(rawValue: keepHistoryRaw) ?? .forever }
        set { keepHistoryRaw = newValue.rawValue }
    }

    var pasteStackDefaultDirection: PasteStackController.Direction {
        get {
            PasteStackController.Direction(rawValue: pasteStackDefaultDirectionRaw) ?? .oldestFirst
        }
        set {
            pasteStackDefaultDirectionRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var ignoredBundleIdentifiers: Set<String> {
        get { Set(Self.lines(from: ignoredBundleIdentifiersRaw)) }
        set {
            ignoredBundleIdentifiersRaw = newValue.sorted().joined(separator: "\n")
            objectWillChange.send()
        }
    }

    var ignoredBundleIdentifiersText: String {
        get { ignoredBundleIdentifiersRaw }
        set { ignoredBundleIdentifiersRaw = newValue }
    }

    var ignoredPasteboardTypes: Set<String> {
        get { Set(Self.lines(from: ignoredPasteboardTypesRaw)) }
        set { ignoredPasteboardTypesRaw = newValue.sorted().joined(separator: "\n") }
    }

    var ignoredPasteboardTypesText: String {
        get { ignoredPasteboardTypesRaw }
        set { ignoredPasteboardTypesRaw = newValue }
    }

    func isIgnored(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return ignoredBundleIdentifiers.contains(bundleIdentifier)
    }

    func ignoresPasteboardType(_ rawType: String) -> Bool {
        ignoredPasteboardTypes.contains(rawType)
    }

    private static func lines(from value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private let defaultIgnoredApps = [
    "com.agilebits.onepassword7",
    "com.1password.1password",
    "com.lastpass.LastPass",
    "com.bitwarden.desktop",
    "com.apple.keychainaccess"
]

private let defaultIgnoredTypes = [
    "org.nspasteboard.TransientType",
    "org.nspasteboard.ConcealedType",
    "org.nspasteboard.AutoGeneratedType",
    "com.agilebits.onepassword",
    "com.typeit4me.clipping",
    "de.petermaurer.TransientPasteboardType",
    "net.antelle.keeweb",
    "Pasteboard generator type"
]
