import Foundation

struct SearchService {
    func search(
        clips: [ClipItem],
        query: String,
        selectedType: ClipType?,
        sourceApp: String?,
        pinboardID: UUID?,
        foldedHaystack: ((ClipItem) -> String)? = nil
    ) -> [ClipItem] {
        let parsed = SearchQuery(rawValue: query)
        let foldedTerms = parsed.terms.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }

        return clips.filter { item in
            if let selectedType, item.primaryType != selectedType {
                return false
            }
            if let sourceApp, item.sourceAppName != sourceApp {
                return false
            }
            if let pinboardID, !item.pinboardIDs.contains(pinboardID) {
                return false
            }
            if let type = parsed.type, item.primaryType != type {
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
    let type: ClipType?
    let app: String?
    let dateRange: ClosedRange<Date>?

    init(rawValue: String) {
        var terms: [String] = []
        var type: ClipType?
        var app: String?
        var dateRange: ClosedRange<Date>?

        for token in rawValue.split(separator: " ").map(String.init) {
            if token.hasPrefix("type:") {
                let value = String(token.dropFirst("type:".count)).lowercased()
                type = ClipType.allCases.first { $0.rawValue == value || $0.title.lowercased() == value }
            } else if token.hasPrefix("app:") {
                app = String(token.dropFirst("app:".count))
            } else if token.hasPrefix("date:") {
                dateRange = Self.dateRange(for: String(token.dropFirst("date:".count)))
            } else {
                terms.append(token)
            }
        }

        self.terms = terms
        self.type = type
        self.app = app
        self.dateRange = dateRange
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
