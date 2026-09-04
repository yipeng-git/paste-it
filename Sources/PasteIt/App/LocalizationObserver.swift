import AppKit
import Foundation

extension Notification.Name {
    /// Posted when macOS preferred language changes and localized UI should refresh.
    static let pasteItLocaleDidChange = Notification.Name("PasteItLocaleDidChange")
}

/// Watches system / per-app language changes and notifies the app to refresh UI.
@MainActor
final class LocalizationObserver {
    private var observers: [NSObjectProtocol] = []
    private var distributedObserver: NSObjectProtocol?
    private var lastLanguageKey = LocalizationObserver.preferredLanguageKey
    private var onChange: (() -> Void)?

    static var preferredLanguageKey: String {
        Locale.preferredLanguages.first ?? Locale.current.identifier
    }

    func start(onChange: @escaping () -> Void) {
        guard observers.isEmpty else {
            self.onChange = onChange
            return
        }
        self.onChange = onChange
        lastLanguageKey = Self.preferredLanguageKey

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.checkForChange() }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.checkForChange() }
            }
        )

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleLanguagesDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkForChange() }
        }
    }

    func stop() {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }
        onChange = nil
    }

    private func checkForChange() {
        let current = Self.preferredLanguageKey
        guard current != lastLanguageKey else { return }
        lastLanguageKey = current
        onChange?()
    }
}
