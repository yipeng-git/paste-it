import AppKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var clips: [ClipItem] = []
    @Published private(set) var pinboards: [Pinboard] = []

    let container: ModelContainer
    let context: ModelContext

    private let blobStore: BlobStore
    private let settings: AppSettings
    private let linkMetadataService = LinkMetadataService.shared
    private let visualCache = ClipVisualCache.shared
    private var enrichingIDs = Set<UUID>()
    private var contentHashIndex: [String: UUID] = [:]
    private var foldedSearchByID: [UUID: String] = [:]
    private var addsSinceLastPrune = 0
    private let pruneEveryNAdds = 25
    private var pendingBlobPruneTask: Task<Void, Never>?
    private let storeURL: URL

    private static let didPurgeSourceIconPNGKey = "didPurgeSourceIconPNG_v1"
    private static let needsHistoryStoreVacuumKey = "needsHistoryStoreVacuum_v1"
    private static let didSeedWelcomeClipsKey = "didSeedWelcomeClips_v1"

    /// True when `history.store` did not exist before this process opened it (true first install).
    private let isFreshStore: Bool

    init(blobStore: BlobStore, settings: AppSettings) {
        self.blobStore = blobStore
        self.settings = settings

        let schema = Schema([ClipItem.self, Pinboard.self])
        // Never use the SwiftData default URL (`Application Support/default.store`):
        // unsandboxed Mac apps share that path and will corrupt each other's stores.
        let storeURL = blobStore.rootURL.appendingPathComponent("history.store")
        self.storeURL = storeURL
        try? FileManager.default.createDirectory(
            at: blobStore.rootURL,
            withIntermediateDirectories: true
        )

        self.isFreshStore = !FileManager.default.fileExists(atPath: storeURL.path)

        // Prefer VACUUM before SwiftData opens the file (deferred from a prior purge).
        if UserDefaults.standard.bool(forKey: Self.needsHistoryStoreVacuumKey) {
            if Self.compactStore(at: storeURL) {
                UserDefaults.standard.set(false, forKey: Self.needsHistoryStoreVacuumKey)
            }
        }

        let configuration = ModelConfiguration(
            "PasteItHistory",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            NSLog("PasteIt: failed to open history store at \(storeURL.path): \(error)")
            // Last resort: ephemeral store so the app can still launch.
            let fallback = ModelConfiguration(
                "PasteItHistoryInMemory",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            container = try! ModelContainer(for: schema, configurations: [fallback])
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() {
        refresh()
        if pinboards.isEmpty {
            createDefaultPinboards()
        }
        seedWelcomeClipsIfNeeded()
        purgeEmbeddedSourceIconsIfNeeded()
        pruneHistory(force: true)
    }

    func refresh() {
        let clipDescriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let pinboardDescriptor = FetchDescriptor<Pinboard>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        clips = (try? context.fetch(clipDescriptor)) ?? []
        pinboards = (try? context.fetch(pinboardDescriptor)) ?? []
        rebuildIndexes()
    }

    func foldedSearchText(for item: ClipItem) -> String {
        if let cached = foldedSearchByID[item.id] {
            return cached
        }
        let folded = item.foldedSearchHaystack
        foldedSearchByID[item.id] = folded
        return folded
    }

    func add(_ capturedClip: CapturedClip) {
        if clips.first?.duplicateContentKey == capturedClip.duplicateContentKey {
            return
        }

        if let existingID = contentHashIndex[capturedClip.contentHash],
           let existing = clips.first(where: { $0.id == existingID }) {
            existing.touchDuplicate()
            // Move to front without a full refetch.
            clips.removeAll { $0.id == existing.id }
            clips.insert(existing, at: 0)
            saveQuietly()
            objectWillChange.send()
            return
        }

        let item = capturedClip.makeModel()
        context.insert(item)
        if !saveQuietly() {
            return
        }
        clips.insert(item, at: 0)
        contentHashIndex[item.contentHash] = item.id
        foldedSearchByID[item.id] = item.foldedSearchHaystack
        objectWillChange.send()

        if let blobPath = capturedClip.pendingOCRBlobRelativePath {
            scheduleOCR(for: item.id, blobRelativePath: blobPath)
        }

        addsSinceLastPrune += 1
        if addsSinceLastPrune >= pruneEveryNAdds {
            addsSinceLastPrune = 0
            pruneHistory(force: false)
        }
        enrichLinkMetadataIfNeeded(for: item.id)
    }

    func updateOCRText(for id: UUID, text: String?) {
        guard let text, !text.isEmpty else { return }
        guard let item = clips.first(where: { $0.id == id }) ?? fetchClip(id: id) else { return }
        item.ocrText = text
        item.updatedAt = Date()
        foldedSearchByID[id] = item.foldedSearchHaystack
        saveQuietly()
        // Avoid full array replace — notify observers that searchable content changed.
        objectWillChange.send()
    }

    func update(
        _ item: ClipItem,
        title: String? = nil,
        plainText: String? = nil,
        htmlText: String? = nil,
        rtfData: Data? = nil
    ) {
        let oldHash = item.contentHash
        if let title {
            item.title = title
        }
        if let plainText {
            item.plainText = plainText
            item.contentHash = DataHashing.sha256(plainText)
        }
        if let htmlText {
            item.htmlText = htmlText
        }
        if let rtfData {
            item.rtfData = rtfData
        }
        item.updatedAt = Date()
        visualCache.invalidate(clipID: item.id)
        if oldHash != item.contentHash {
            if contentHashIndex[oldHash] == item.id {
                contentHashIndex.removeValue(forKey: oldHash)
            }
            contentHashIndex[item.contentHash] = item.id
        }
        foldedSearchByID[item.id] = item.foldedSearchHaystack
        saveQuietly()
        objectWillChange.send()
    }

    @discardableResult
    func saveAsNew(
        from item: ClipItem,
        title: String,
        plainText: String,
        htmlText: String? = nil,
        rtfData: Data? = nil
    ) -> ClipItem {
        let resolvedType: ClipType
        if htmlText != nil {
            resolvedType = .html
        } else if rtfData != nil {
            resolvedType = .richText
        } else if plainText.looksLikeURL {
            resolvedType = .url
        } else {
            resolvedType = .text
        }

        let newItem = ClipItem(
            title: title,
            plainText: plainText,
            htmlText: htmlText,
            rtfData: rtfData,
            primaryType: resolvedType,
            pasteboardTypes: item.pasteboardTypes,
            sourceAppName: item.sourceAppName,
            sourceBundleIdentifier: item.sourceBundleIdentifier,
            sourceIconPNG: nil,
            blobRelativePath: nil,
            thumbnailRelativePath: nil,
            fileURLString: plainText.looksLikeURL ? plainText.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            ocrText: nil,
            linkTitle: nil,
            linkIconRelativePath: nil,
            linkImageRelativePath: nil,
            pinboardIDs: [],
            contentHash: DataHashing.sha256(plainText)
        )
        context.insert(newItem)
        saveQuietly()
        clips.insert(newItem, at: 0)
        contentHashIndex[newItem.contentHash] = newItem.id
        foldedSearchByID[newItem.id] = newItem.foldedSearchHaystack
        objectWillChange.send()
        enrichLinkMetadataIfNeeded(for: newItem.id)
        return newItem
    }

    func delete(_ item: ClipItem) {
        for pinboard in pinboards where pinboard.itemIDs.contains(item.id) {
            pinboard.itemIDs.removeAll { $0 == item.id }
        }
        visualCache.invalidate(clipID: item.id)
        visualCache.invalidatePath(item.thumbnailRelativePath)
        visualCache.invalidatePath(item.blobRelativePath)
        visualCache.invalidatePath(item.linkIconRelativePath)
        visualCache.invalidatePath(item.linkImageRelativePath)
        if contentHashIndex[item.contentHash] == item.id {
            contentHashIndex.removeValue(forKey: item.contentHash)
        }
        foldedSearchByID.removeValue(forKey: item.id)
        context.delete(item)
        clips.removeAll { $0.id == item.id }
        saveQuietly()
        objectWillChange.send()
    }

    func thumbnailImage(for item: ClipItem) -> NSImage? {
        visualCache.image(at: item.thumbnailRelativePath, blobStore: blobStore)
    }

    /// Cache hit only — never blocks the main thread on disk IO.
    func cachedThumbnailImage(for item: ClipItem) -> NSImage? {
        visualCache.cachedImage(at: item.thumbnailRelativePath)
    }

    func loadThumbnailImage(for item: ClipItem) async -> NSImage? {
        await visualCache.loadImage(at: item.thumbnailRelativePath, blobStore: blobStore)
    }

    func fullImage(for item: ClipItem) -> NSImage? {
        visualCache.image(at: item.blobRelativePath, blobStore: blobStore)
    }

    func linkIconImage(for item: ClipItem) -> NSImage? {
        visualCache.image(at: item.linkIconRelativePath, blobStore: blobStore)
    }

    func cachedLinkPreviewImage(for item: ClipItem) -> NSImage? {
        visualCache.cachedImage(at: item.linkImageRelativePath)
            ?? visualCache.cachedImage(at: item.linkIconRelativePath)
    }

    func loadLinkPreviewImage(for item: ClipItem) async -> NSImage? {
        if let preview = await visualCache.loadImage(at: item.linkImageRelativePath, blobStore: blobStore) {
            return preview
        }
        return await visualCache.loadImage(at: item.linkIconRelativePath, blobStore: blobStore)
    }

    func linkPreviewImage(for item: ClipItem) -> NSImage? {
        visualCache.image(at: item.linkImageRelativePath, blobStore: blobStore)
    }

    func sourceIcon(for item: ClipItem) -> NSImage? {
        visualCache.sourceIcon(for: item)
    }

    func bannerColor(for item: ClipItem) -> Color {
        visualCache.bannerColor(for: item)
    }

    func blobURL(for item: ClipItem) -> URL? {
        blobStore.url(for: item.blobRelativePath)
    }

    /// Pixel dimensions of the stored image blob, falling back to thumbnail.
    func imagePixelSize(for item: ClipItem) -> (width: Int, height: Int)? {
        if let stored = item.storedImagePixelSize {
            return stored
        }
        return visualCache.pixelSize(for: item, blobStore: blobStore)
    }

    func enrichLinkMetadataIfNeeded(for item: ClipItem) {
        enrichLinkMetadataIfNeeded(for: item.id)
    }

    func enrichLinkMetadataIfNeeded(for id: UUID) {
        guard let item = clips.first(where: { $0.id == id }) ?? fetchClip(id: id) else { return }
        guard item.primaryType == .url else { return }
        guard item.linkTitle == nil, item.linkIconRelativePath == nil, item.linkImageRelativePath == nil else {
            return
        }
        guard !enrichingIDs.contains(id) else { return }

        let urlString = item.fileURLString ?? item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return
        }

        enrichingIDs.insert(id)
        Task { @MainActor in
            defer { enrichingIDs.remove(id) }
            let metadata = await linkMetadataService.metadata(for: url)
            guard let liveItem = clips.first(where: { $0.id == id }) ?? fetchClip(id: id) else { return }

            var didUpdate = false
            if let title = metadata.title, !title.isEmpty {
                liveItem.linkTitle = title
                if liveItem.title == liveItem.plainText || liveItem.title.count > 80 {
                    liveItem.title = String(title.prefix(80))
                }
                didUpdate = true
            }
            if let iconData = metadata.iconData {
                liveItem.linkIconRelativePath = try? blobStore.store(
                    data: iconData,
                    preferredExtension: "png",
                    id: UUID()
                )
                didUpdate = true
            }
            if let imageData = metadata.imageData {
                liveItem.linkImageRelativePath = try? blobStore.store(
                    data: imageData,
                    preferredExtension: "jpg",
                    id: UUID()
                )
                didUpdate = true
            }

            if didUpdate {
                liveItem.updatedAt = Date()
                visualCache.invalidate(clipID: id)
                foldedSearchByID[id] = liveItem.foldedSearchHaystack
                saveQuietly()
                objectWillChange.send()
            }
        }
    }

    func clearHistory(keepPinned: Bool = true) {
        let victims = clips.filter { keepPinned ? $0.pinboardIDs.isEmpty : true }
        for item in victims {
            if contentHashIndex[item.contentHash] == item.id {
                contentHashIndex.removeValue(forKey: item.contentHash)
            }
            foldedSearchByID.removeValue(forKey: item.id)
            visualCache.invalidate(clipID: item.id)
            context.delete(item)
        }
        clips.removeAll { item in
            victims.contains(where: { $0.id == item.id })
        }
        saveQuietly()
        objectWillChange.send()
    }

    @discardableResult
    func createPinboard(name: String, colorHex: String = "#6C7BFF") -> Pinboard {
        let pinboard = Pinboard(name: name, colorHex: colorHex)
        context.insert(pinboard)
        saveQuietly()
        pinboards.append(pinboard)
        objectWillChange.send()
        return pinboard
    }

    func renamePinboard(_ pinboard: Pinboard, name: String) {
        pinboard.name = name
        pinboard.updatedAt = Date()
        saveQuietly()
        objectWillChange.send()
    }

    func deletePinboard(_ pinboard: Pinboard) {
        for item in clips where item.pinboardIDs.contains(pinboard.id) {
            item.pinboardIDs.removeAll { $0 == pinboard.id }
            foldedSearchByID[item.id] = item.foldedSearchHaystack
        }
        context.delete(pinboard)
        pinboards.removeAll { $0.id == pinboard.id }
        saveQuietly()
        objectWillChange.send()
    }

    func pin(_ item: ClipItem, to pinboard: Pinboard) {
        if !item.pinboardIDs.contains(pinboard.id) {
            item.pinboardIDs.append(pinboard.id)
        }
        if !pinboard.itemIDs.contains(item.id) {
            pinboard.itemIDs.insert(item.id, at: 0)
        }
        saveQuietly()
        objectWillChange.send()
    }

    /// Pins to Favorites (creating it if needed) so the item survives history pruning.
    func pinToDefaultBoard(_ item: ClipItem) {
        let board = pinboards.first(where: { $0.name == "Favorites" })
            ?? createPinboard(name: "Favorites", colorHex: "#6C7BFF")
        pin(item, to: board)
    }

    func unpin(_ item: ClipItem, from pinboard: Pinboard? = nil) {
        if let pinboard {
            item.pinboardIDs.removeAll { $0 == pinboard.id }
            pinboard.itemIDs.removeAll { $0 == item.id }
        } else {
            for pinboard in pinboards {
                pinboard.itemIDs.removeAll { $0 == item.id }
            }
            item.pinboardIDs = []
        }
        saveQuietly()
        objectWillChange.send()
    }

    func pruneHistory(force: Bool = true) {
        var didDelete = false
        if let cutoff = settings.keepHistory.cutoffDate {
            let expired = clips.filter { $0.createdAt < cutoff && $0.pinboardIDs.isEmpty }
            for item in expired {
                removeFromIndexes(item)
                context.delete(item)
                didDelete = true
            }
            if !expired.isEmpty {
                clips.removeAll { item in expired.contains(where: { $0.id == item.id }) }
            }
        }

        let unpinned = clips.filter { $0.pinboardIDs.isEmpty }
        if unpinned.count > settings.maxHistoryItems {
            let overflow = Array(unpinned.dropFirst(settings.maxHistoryItems))
            for item in overflow {
                removeFromIndexes(item)
                context.delete(item)
                didDelete = true
            }
            let overflowIDs = Set(overflow.map(\.id))
            clips.removeAll { overflowIDs.contains($0.id) }
        }

        if didDelete {
            saveQuietly()
            objectWillChange.send()
        }

        scheduleBlobPrune()
    }

    // MARK: - Private

    private func scheduleOCR(for id: UUID, blobRelativePath: String) {
        let store = blobStore
        Task.detached(priority: .utility) {
            guard let data = store.data(for: blobRelativePath) else { return }
            let text = await OCRService.recognizeText(in: data)
            await MainActor.run {
                self.updateOCRText(for: id, text: text)
            }
        }
    }

    private func scheduleBlobPrune() {
        pendingBlobPruneTask?.cancel()
        let maxMB = settings.maxBlobMegabytes
        let store = blobStore
        pendingBlobPruneTask = Task.detached(priority: .utility) {
            store.prune(maxMegabytes: maxMB)
        }
    }

    private func removeFromIndexes(_ item: ClipItem) {
        if contentHashIndex[item.contentHash] == item.id {
            contentHashIndex.removeValue(forKey: item.contentHash)
        }
        foldedSearchByID.removeValue(forKey: item.id)
        visualCache.invalidate(clipID: item.id)
        visualCache.invalidatePath(item.thumbnailRelativePath)
        visualCache.invalidatePath(item.blobRelativePath)
        visualCache.invalidatePath(item.linkIconRelativePath)
        visualCache.invalidatePath(item.linkImageRelativePath)
    }

    private func rebuildIndexes() {
        contentHashIndex.removeAll(keepingCapacity: true)
        foldedSearchByID.removeAll(keepingCapacity: true)
        for item in clips {
            contentHashIndex[item.contentHash] = item.id
            foldedSearchByID[item.id] = item.foldedSearchHaystack
        }
    }

    private func fetchClip(id: UUID) -> ClipItem? {
        let descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func createDefaultPinboards() {
        context.insert(Pinboard(name: "Favorites", colorHex: "#6C7BFF"))
        context.insert(Pinboard(name: "Templates", colorHex: "#35C759"))
        saveQuietly()
        refresh()
    }

    /// First install only: three starter clips. Overwrite/upgrade keeps `history.store`
    /// and/or `didSeedWelcomeClips_v1`, so this never re-injects into existing libraries.
    private func seedWelcomeClipsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.didSeedWelcomeClipsKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: Self.didSeedWelcomeClipsKey) }

        guard isFreshStore, clips.isEmpty else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "app.paste-it.mac"
        let now = Date()

        let welcome = ClipItem(
            createdAt: now,
            title: "Welcome to Paste It",
            plainText: "Welcome to Paste It",
            primaryType: .text,
            pasteboardTypes: ["public.utf8-plain-text"],
            sourceAppName: "Paste It",
            sourceBundleIdentifier: bundleID,
            contentHash: DataHashing.sha256("welcome-to-paste-it-seed-v1")
        )

        let websiteURL = "https://paste-it.app"
        let website = ClipItem(
            createdAt: now.addingTimeInterval(-1),
            title: "paste-it.app",
            plainText: websiteURL,
            primaryType: .url,
            pasteboardTypes: ["public.url", "public.utf8-plain-text"],
            sourceAppName: "Paste It",
            sourceBundleIdentifier: bundleID,
            fileURLString: websiteURL,
            linkTitle: "Paste It",
            contentHash: DataHashing.sha256(websiteURL)
        )

        let githubURL = "https://github.com/yipeng-git/paste-it"
        let github = ClipItem(
            createdAt: now.addingTimeInterval(-2),
            title: "GitHub",
            plainText: githubURL,
            primaryType: .url,
            pasteboardTypes: ["public.url", "public.utf8-plain-text"],
            sourceAppName: "Paste It",
            sourceBundleIdentifier: bundleID,
            fileURLString: githubURL,
            linkTitle: "yipeng-git/paste-it",
            contentHash: DataHashing.sha256(githubURL)
        )

        // Insert oldest → newest so a failed mid-seed still sorts correctly after refresh.
        for item in [github, website, welcome] {
            context.insert(item)
        }
        guard saveQuietly() else { return }
        refresh()

        enrichLinkMetadataIfNeeded(for: website.id)
        enrichLinkMetadataIfNeeded(for: github.id)
    }

    @discardableResult
    private func saveQuietly() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            // Never crash the clipboard daemon on a failed save — roll back so the
            // context can accept future inserts instead of staying permanently dirty.
            NSLog("PasteIt: SwiftData save failed: \(error)")
            context.rollback()
            return false
        }
    }

    /// One-shot: drop per-clip embedded app icons that bloated history.store (~MB each).
    private func purgeEmbeddedSourceIconsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.didPurgeSourceIconPNGKey) else { return }

        let victims = clips.filter { $0.sourceIconPNG != nil }
        guard !victims.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.didPurgeSourceIconPNGKey)
            return
        }

        for item in victims {
            item.sourceIconPNG = nil
        }
        guard saveQuietly() else {
            NSLog("PasteIt: failed to purge embedded source icons; will retry next launch")
            return
        }
        UserDefaults.standard.set(true, forKey: Self.didPurgeSourceIconPNGKey)
        visualCache.removeAll()
        NSLog("PasteIt: purged sourceIconPNG from \(victims.count) clips")

        // VACUUM while SwiftData holds the store often fails — retry before next open.
        if Self.compactStore(at: storeURL) {
            UserDefaults.standard.set(false, forKey: Self.needsHistoryStoreVacuumKey)
        } else {
            UserDefaults.standard.set(true, forKey: Self.needsHistoryStoreVacuumKey)
            NSLog("PasteIt: history.store VACUUM deferred to next launch")
        }
    }

    /// Checkpoint WAL and VACUUM via sqlite3 CLI. Safe only when the store is not open,
    /// or best-effort while open (may fail with a lock).
    @discardableResult
    nonisolated private static func compactStore(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            url.path,
            "PRAGMA wal_checkpoint(TRUNCATE); VACUUM;"
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("PasteIt: failed to launch sqlite3 for VACUUM: \(error.localizedDescription)")
            return false
        }

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            NSLog(
                "PasteIt: history.store VACUUM failed (status \(process.terminationStatus)): \(errText)"
            )
            return false
        }
        NSLog("PasteIt: compacted history.store at \(url.path)")
        return true
    }
}
