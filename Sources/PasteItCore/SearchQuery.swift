import Foundation

public struct SearchQuery: Sendable {
    public let terms: [String]
    public let filterCategory: FilterCategory?
    public let app: String?
    public let dateRange: ClosedRange<Date>?

    public init(rawValue: String) {
        var terms: [String] = []
        var filterCategory: FilterCategory?
        var app: String?
        var dateRange: ClosedRange<Date>?

        for token in rawValue.split(separator: " ").map(String.init) {
            if token.hasPrefix("type:") {
                let value = String(token.dropFirst("type:".count)).lowercased()
                filterCategory = FilterCategory.from(typeToken: value)
            } else if token.hasPrefix("app:") {
                app = String(token.dropFirst("app:".count))
            } else if token.hasPrefix("date:") {
                dateRange = Self.dateRange(for: String(token.dropFirst("date:".count)))
            } else {
                terms.append(token)
            }
        }

        self.terms = terms
        self.filterCategory = filterCategory
        self.app = app
        self.dateRange = dateRange
    }

    /// Drops `type:` tokens so the filter pill owns type state.
    public static func strippingTypeTokens(from raw: String) -> String {
        raw.split(separator: " ")
            .map(String.init)
            .filter { !$0.lowercased().hasPrefix("type:") }
            .joined(separator: " ")
    }

    private static func dateRange(for value: String) -> ClosedRange<Date>? {
        let calendar = Calendar.current
        let now = Date()
        switch value.lowercased() {
        case "today":
            return calendar.startOfDay(for: now)...now
        case "week":
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            return start...now
        case "month":
            guard let start = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return start...now
        default:
            return nil
        }
    }
}
