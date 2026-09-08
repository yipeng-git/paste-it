import Foundation

/// Value-only input: no SwiftData objects cross an actor boundary.
public struct ClipSearchDocument: Sendable {
    public let id: UUID
    public let revision: Date
    public let type: String
    public let plainText: String
    public let searchText: String
    public let sourceApp: String?
    public let createdAt: Date

    public init(id: UUID, revision: Date, type: String, plainText: String,
                searchText: String, sourceApp: String?, createdAt: Date) {
        self.id = id
        self.revision = revision
        self.type = type
        self.plainText = plainText
        self.searchText = searchText
        self.sourceApp = sourceApp
        self.createdAt = createdAt
    }
}

/// Actor-owned normalization cache. Search preserves input order and cooperatively cancels.
public actor ClipSearchIndex {
    private struct Entry {
        let revision: Date
        let foldedText: String
        let category: FilterCategory?
    }
    private var entries: [UUID: Entry] = [:]
    private let cacheLimit = 20_000
    public init() {}

    public func search(_ documents: [ClipSearchDocument], query: String,
                       filter: FilterCategory, sourceApp: String?) throws -> [UUID] {
        let parsed = SearchQuery(rawValue: query)
        let terms = parsed.terms.map(Self.fold)
        let effective = filter == .all ? parsed.filterCategory ?? .all : filter
        var result: [UUID] = []
        for (index, document) in documents.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            guard passes(document, parsed: parsed, sourceApp: sourceApp) else { continue }
            let entry = entry(for: document)
            guard effective == .all || entry.category == effective else { continue }
            if terms.allSatisfy({ entry.foldedText.contains($0) }) { result.append(document.id) }
        }
        try Task.checkCancellation()
        return result
    }

    public func counts(_ documents: [ClipSearchDocument], query: String,
                       sourceApp: String?) throws -> [FilterCategory: Int] {
        let parsed = SearchQuery(rawValue: query)
        let terms = parsed.terms.map(Self.fold)
        var counts = Dictionary(uniqueKeysWithValues: FilterCategory.menuItems.map { ($0, 0) })
        for (index, document) in documents.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            guard passes(document, parsed: parsed, sourceApp: sourceApp) else { continue }
            let entry = entry(for: document)
            guard terms.allSatisfy({ entry.foldedText.contains($0) }) else { continue }
            counts[.all, default: 0] += 1
            if let category = entry.category { counts[category, default: 0] += 1 }
        }
        try Task.checkCancellation()
        return counts
    }

    private func entry(for document: ClipSearchDocument) -> Entry {
        if let entry = entries[document.id], entry.revision == document.revision { return entry }
        let category = FilterCategory.menuItems.first {
            $0 != .all && $0.matches(primaryTypeRaw: document.type, plainText: document.plainText)
        }
        let entry = Entry(revision: document.revision, foldedText: Self.fold(document.searchText), category: category)
        // Bound retention even when a user searches many different historical records.
        if entries.count >= cacheLimit { entries.removeAll(keepingCapacity: true) }
        entries[document.id] = entry
        return entry
    }

    private func passes(_ document: ClipSearchDocument, parsed: SearchQuery, sourceApp: String?) -> Bool {
        if let sourceApp, document.sourceApp != sourceApp { return false }
        if let app = parsed.app, document.sourceApp?.localizedCaseInsensitiveContains(app) != true { return false }
        if let range = parsed.dateRange, !range.contains(document.createdAt) { return false }
        return true
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
