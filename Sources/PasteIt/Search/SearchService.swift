import Foundation
import PasteItCore

struct SearchService {
    func search(
        clips: [ClipItem],
        query: String,
        selectedFilter: FilterCategory,
        sourceApp: String?,
        pinboardID: UUID?,
        foldedHaystack: ((ClipItem) -> String)? = nil
    ) -> [ClipItem] {
        let parsed = SearchQuery(rawValue: query)
        let foldedTerms = parsed.terms.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        // Pill / selectedFilter is the type source of truth when set; otherwise honor type:.
        let effectiveFilter: FilterCategory = {
            if selectedFilter != .all { return selectedFilter }
            return parsed.filterCategory ?? .all
        }()

        return clips.filter { item in
            if !effectiveFilter.matches(
                primaryTypeRaw: item.primaryType.rawValue,
                plainText: item.plainText
            ) {
                return false
            }
            if let sourceApp, item.sourceAppName != sourceApp {
                return false
            }
            if let pinboardID, !item.pinboardIDs.contains(pinboardID) {
                return false
            }
            if let app = parsed.app, item.sourceAppName?.localizedCaseInsensitiveContains(app) != true {
                return false
            }
            if let dateRange = parsed.dateRange, !dateRange.contains(item.createdAt) {
                return false
            }
            guard !foldedTerms.isEmpty else { return true }

            let haystack = foldedHaystack?(item) ?? item.foldedSearchHaystack
            return foldedTerms.allSatisfy { term in
                haystack.contains(term)
            }
        }
    }
}

struct SearchQuery {
    let terms: [String]
    let filterCategory: FilterCategory?
    let app: String?
    let dateRange: ClosedRange<Date>?

    init(rawValue: String) {
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
    static func strippingTypeTokens(from raw: String) -> String {
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
