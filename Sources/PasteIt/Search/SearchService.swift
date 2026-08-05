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
        let foldedTerms = Self.foldedTerms(from: parsed)
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
            return Self.passesNonTypeFilters(
                item,
                parsed: parsed,
                foldedTerms: foldedTerms,
                sourceApp: sourceApp,
                pinboardID: pinboardID,
                foldedHaystack: foldedHaystack
            )
        }
    }

    /// One pass over `clips`: counts for every `FilterCategory.menuItems` entry under the
    /// current query / source-app / pinboard constraints (type pill is ignored — each
    /// category is counted as if selected).
    func countsByFilter(
        clips: [ClipItem],
        query: String,
        sourceApp: String?,
        pinboardID: UUID?,
        foldedHaystack: ((ClipItem) -> String)? = nil
    ) -> [FilterCategory: Int] {
        let parsed = SearchQuery(rawValue: query)
        let foldedTerms = Self.foldedTerms(from: parsed)
        var counts = Dictionary(uniqueKeysWithValues: FilterCategory.menuItems.map { ($0, 0) })

        for item in clips {
            guard Self.passesNonTypeFilters(
                item,
                parsed: parsed,
                foldedTerms: foldedTerms,
                sourceApp: sourceApp,
                pinboardID: pinboardID,
                foldedHaystack: foldedHaystack
            ) else { continue }

            counts[.all, default: 0] += 1
            let typeRaw = item.primaryType.rawValue
            let plain = item.plainText
            for category in FilterCategory.menuItems where category != .all {
                if category.matches(primaryTypeRaw: typeRaw, plainText: plain) {
                    counts[category, default: 0] += 1
                }
            }
        }
        return counts
    }

    private static func foldedTerms(from parsed: SearchQuery) -> [String] {
        parsed.terms.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
    }

    private static func passesNonTypeFilters(
        _ item: ClipItem,
        parsed: SearchQuery,
        foldedTerms: [String],
        sourceApp: String?,
        pinboardID: UUID?,
        foldedHaystack: ((ClipItem) -> String)?
    ) -> Bool {
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
