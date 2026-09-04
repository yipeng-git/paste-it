import Foundation

/// Shared localization helper. The app target sets `bundle` to its resource bundle at launch.
public enum L10n {
    nonisolated(unsafe) public static var bundle: Bundle = .main

    public static func tr(_ key: String, default defaultValue: String) -> String {
        bundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    public static func tr(_ key: String, default defaultValue: String, _ arguments: CVarArg...) -> String {
        let format = tr(key, default: defaultValue)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
