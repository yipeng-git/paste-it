import AppKit
import Combine
import PasteItCore
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class HistoryStore: ObservableObject {
    private struct Removal {
        let id = UUID()
        let snapshot: ClipItem
        let tab: TimelineTab
        let nextID: UUID?
        let boardNextIDs: [UUID: UUID]
        let expiresAt: Date
    }
    private var removals: [Removal] = []
    private var removalExpiryTask: Task<Void, Never>?
    @Published private(set) var latestRemovalID: UUID?
    @Published private(set) var canUndoRemoval = false
    @Published var removalError: String?

    /// Up to 20 removals, each recoverable for 30 seconds in this running session.
    func expireRemovalUndo(now: Date = Date()) {
        removals.removeAll { $0.expiresAt <= now }
        updateRemovalProtection()
    }

    private func updateRemovalProtection() {
        latestRemovalID = removals.last?.id
        canUndoRemoval = !removals.isEmpty
        blobStore.protectForUndo(removals.reduce(into: Set<String>()) { $0.formUnion($1.snapshot.attachmentPaths) })
        removalExpiryTask?.cancel()
        guard let expiry = removals.map(\.expiresAt).min() else { return }
        removalExpiryTask = Task { @MainActor [weak self] in
            let delay = max(0.01, expiry.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.expireRemovalUndo()
        }
    }

    func discardRemovalUndo() {
        removals.removeAll()
        updateRemovalProtection()
    }

    @discardableResult
    func undoLastRemoval(expectedID: UUID? = nil) -> (item: ClipItem, tab: TimelineTab)? {
        expireRemovalUndo()
        guard let removal = removals.last, expectedID == nil || removal.id == expectedID else { return nil }
        let snapshot = removal.snapshot
        let item: ClipItem
        let existing = clips.first { $0.id == snapshot.id }
            ?? clips.first { $0.duplicateContentKey == snapshot.duplicateContentKey }
        if let existing {
            item = existing
            if removal.tab == .timeline { item.isHiddenFromTimeline = snapshot.isHiddenFromTimeline }
        } else {
            item = snapshot.removalSnapshot()
            context.insert(item)
        }
        let liveBoardIDs = Set(pinboards.map(\.id))
        item.pinboardIDs = Array(Set(item.pinboardIDs + snapshot.pinboardIDs).intersection(liveBoardIDs))
        // A folder removed since the action cannot be restored by clip undo; keep the clip reachable.
        if item.pinboardIDs.isEmpty { item.isHiddenFromTimeline = false }
        for board in pinboards where item.pinboardIDs.contains(board.id) {
            guard !board.itemIDs.contains(item.id) else { continue }
            var ids = board.itemIDs
            let position = removal.boardNextIDs[board.id].flatMap { ids.firstIndex(of: $0) } ?? ids.count
            ids.insert(item.id, at: position)
            board.itemIDs = ids
        }
        if existing == nil { item.updatedAt = snapshot.updatedAt }
        guard saveQuietly() else {
            context.rollback()
            refresh()
            removalError = L10n.tr("removal.saveFailed", default: "Could not save the change. Your history has been restored; try again.")
            return nil
        }
        if existing == nil {
            let index = removal.nextID.flatMap { next in clips.firstIndex { $0.id == next } }
                ?? clips.firstIndex(where: { $0.lastUsedAt < snapshot.lastUsedAt })
                ?? clips.count
            clips.insert(item, at: index)
        }
        removals.removeLast()
        rebuildIndexes()
        updateRemovalProtection()
        notifyChange()
        if case .folder(let id) = removal.tab, !liveBoardIDs.contains(id) {
            return (item, .timeline)
        }
        return (item, removal.tab)
    }

    func clearHistoryCandidates(keepSaved: Bool) -> [ClipItem] {
        clips.filter { !keepSaved || $0.pinboardIDs.isEmpty }
    }

    func retentionCandidates(_ retention: AppSettings.KeepHistory) -> [ClipItem] {
        guard let cutoff = retention.cutoffDate else { return [] }
        return clips.filter { $0.pinboardIDs.isEmpty && $0.createdAt < cutoff }
    }

    func pruneCandidates() -> [ClipItem] {
        let unsaved = clips.filter { $0.pinboardIDs.isEmpty }
        let expired = Set(retentionCandidates(settings.keepHistory).map(\.id))
        let remaining = unsaved.filter { !expired.contains($0.id) }
        let overflow = Set(remaining.dropFirst(max(0, settings.maxHistoryItems)).map(\.id))
        return unsaved.filter { expired.contains($0.id) || overflow.contains($0.id) }
    }

    /// Delete exactly the reviewed set. New captures after the confirmation opened survive.
    @discardableResult
    func deleteReviewedClips(ids: Set<UUID>, keepSaved: Bool, endAllUndo: Bool = true) -> Bool {
        let victims = clips.filter { ids.contains($0.id) && (!keepSaved || $0.pinboardIDs.isEmpty) }
        let victimIDs = Set(victims.map(\.id))
        let victimKeys = Set(victims.map(\.duplicateContentKey))
        for board in pinboards { board.itemIDs.removeAll { victimIDs.contains($0) } }
        for item in victims { context.delete(item) }
        guard saveQuietly() else {
            context.rollback()
            refresh()
            removalError = L10n.tr("removal.saveFailed", default: "Could not save the change. Your history has been restored; try again.")
            return false
        }
        if endAllUndo {
            discardRemovalUndo()
        } else {
            removals.removeAll { victimIDs.contains($0.snapshot.id) || victimKeys.contains($0.snapshot.duplicateContentKey) }
            updateRemovalProtection()
        }
        clips.removeAll { victimIDs.contains($0.id) }
        rebuildIndexes()
        notifyChange()
        return true
    }

    func deleteEverywhere(_ item: ClipItem) {
        _ = deleteReviewedClips(ids: [item.id], keepSaved: false, endAllUndo: false)
    }

    @Published private(set) var revision: UInt64 = 0
    struct Change {
        var collectionChanged = false
        var contentIDs = Set<UUID>()
    }
    let changes = PassthroughSubject<Change, Never>()
    private var pendingChange: Change?
    private(set) var clips: [ClipItem] = [] {
        didSet { notifyChange() }
    }
    private(set) var pinboards: [Pinboard] = [] {
        didSet { notifyChange() }
    }

    /// Publish after a logical transaction, coalescing array edits and model changes.
    private func notifyChange(contentID: UUID? = nil) {
        let needsSchedule = pendingChange == nil
        var change = pendingChange ?? Change()
        if let contentID { change.contentIDs.insert(contentID) }
        else { change.collectionChanged = true }
        pendingChange = change
        guard needsSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let change = self.pendingChange else { return }
            self.pendingChange = nil
            self.revision &+= 1
            self.changes.send(change)
        }
    }

    let container: ModelContainer
    let context: ModelContext

    let blobStore: BlobStore
    private let settings: AppSettings
    private let linkMetadataService = LinkMetadataService.shared
    private let visualCache = ClipVisualCache.shared
    private var enrichingIDs = Set<UUID>()
    private var contentHashIndex: [String: UUID] = [:]
    private var foldedSearchByID: [UUID: String] = [:]
    private var searchDocumentsByID: [UUID: ClipSearchDocument] = [:]
    private var addsSinceLastPrune = 0
    private let pruneEveryNAdds = 25
    private var pendingBlobPruneTask: Task<Void, Never>?
    private let storeURL: URL

    private static let didPurgeSourceIconPNGKey = "didPurgeSourceIconPNG_v1"
    private static let needsHistoryStoreVacuumKey = "needsHistoryStoreVacuum_v1"
    private static let didSeedWelcomeClipsKey = "didSeedWelcomeClips_v1"
    private static let didBackfillLastUsedAtKey = "didBackfillLastUsedAt_v1"

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

    /// In-memory history for Agent API ephemeral timeline screenshots. Never touches disk history.
    init(ephemeralBlobRoot: URL, settings: AppSettings) {
        try? FileManager.default.createDirectory(at: ephemeralBlobRoot, withIntermediateDirectories: true)
        self.blobStore = BlobStore(rootURL: ephemeralBlobRoot)
        self.settings = settings
        self.storeURL = ephemeralBlobRoot.appendingPathComponent("ephemeral.store")
        self.isFreshStore = true

        let schema = Schema([ClipItem.self, Pinboard.self])
        let configuration = ModelConfiguration(
            "PasteItEphemeral-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        container = try! ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    /// Stores image bytes into this store's blob root (used by ephemeral seed).
    func ingestImageData(_ data: Data) throws -> (
        blobRelativePath: String,
        thumbnailRelativePath: String?,
        pixelWidth: Int?,
        pixelHeight: Int?
    ) {
        let id = UUID()
        let blobPath = try blobStore.store(data: data, preferredExtension: "png", id: id)
        let thumb = try blobStore.storeThumbnail(fromImageData: data, id: id)
        return (blobPath, thumb?.path, thumb?.pixelWidth, thumb?.pixelHeight)
    }

    /// Removes the ephemeral blob root from disk (no-op for persistent stores).
    func destroyEphemeralFiles() {
        let root = blobStore.rootURL
        // Never delete the real Application Support PasteIt root.
        guard root.path.contains("PasteItEphemeral") else { return }
        try? FileManager.default.removeItem(at: root)
    }

    func load() {
        refresh()
        backfillLastUsedAtIfNeeded()
        migratePinnedPinboardIfNeeded()
        if pinboards.isEmpty {
            createDefaultPinboards()
        } else {
            _ = ensurePinnedPinboard()
        }
        seedWelcomeClipsIfNeeded()
        purgeEmbeddedSourceIconsIfNeeded()
        pruneHistory(force: true)
    }

    func refresh() {
        let clipDescriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
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

    func searchDocuments(for items: [ClipItem]) -> [ClipSearchDocument] {
        items.map { item in
            if let cached = searchDocumentsByID[item.id], cached.revision == item.updatedAt { return cached }
            let document = ClipSearchDocument(
                id: item.id, revision: item.updatedAt, type: item.primaryTypeRaw,
                plainText: item.plainText, searchText: item.searchableText,
                sourceApp: item.sourceAppName, createdAt: item.createdAt
            )
            searchDocumentsByID[item.id] = document
            return document
        }
    }

    /// Moves a clip to the front of history after copy / paste from the timeline.
    /// Mirrors Paste: bumps `timestamp` (`lastUsedAt`), keeps original `createdAt`.
    func promoteToFront(_ item: ClipItem) {
        guard clips.contains(where: { $0.id == item.id }) else { return }
        item.touchAccess()
        if clips.first?.id != item.id {
            clips.removeAll { $0.id == item.id }
            clips.insert(item, at: 0)
        }
        saveQuietly()
        notifyChange()
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
            notifyChange()
            return
        }

        let item = capturedClip.makeModel()
        context.insert(item)
        if !saveQuietly() {
            return
        }
        clips.insert(item, at: 0)
        contentHashIndex[item.contentHash] = item.id
        foldedSearchByID.removeValue(forKey: item.id)
        searchDocumentsByID.removeValue(forKey: item.id)
        notifyChange()

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

    /// Updates searchable OCR text for an image clip.
    /// - Parameter allowEmpty: When true, `nil` / blank clears `ocrText` (user edit).
    ///   When false (default), empty results are ignored so a failed re-run cannot wipe text.
    func updateOCRText(for id: UUID, text: String?, allowEmpty: Bool = false) {
        guard let item = clips.first(where: { $0.id == id }) ?? fetchClip(id: id) else { return }
        let normalized = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            item.ocrText = normalized
        } else if allowEmpty {
            item.ocrText = nil
        } else {
            return
        }
        item.updatedAt = Date()
        foldedSearchByID.removeValue(forKey: id)
        saveQuietly()
        // Only this item changed; do not invalidate unfiltered tab membership.
        notifyChange(contentID: id)
    }

    /// Re-runs Vision OCR on the clip's image blob and writes the result back.
    func rerunOCR(for item: ClipItem) async {
        guard let blobPath = item.blobRelativePath, !blobPath.isEmpty else { return }
        let store = blobStore
        let id = item.id
        let text = await Task.detached(priority: .utility) { () -> String? in
            guard let data = store.data(for: blobPath) else { return nil }
            return await OCRService.recognizeText(in: data)
        }.value
        updateOCRText(for: id, text: text)
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
        foldedSearchByID.removeValue(forKey: item.id)
        searchDocumentsByID.removeValue(forKey: item.id)
        saveQuietly()
        notifyChange(contentID: item.id)
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
        foldedSearchByID.removeValue(forKey: newItem.id)
        notifyChange()
        enrichLinkMetadataIfNeeded(for: newItem.id)
        return newItem
    }

    func delete(_ item: ClipItem) {
        for pinboard in pinboards where pinboard.itemIDs.contains(item.id) {
            pinboard.itemIDs.removeAll { $0 == item.id }
        }
        visualCache.invalidate(clipID: item.id)
        visualCache.invalidatePath(item.thumbnailRelativePath, blobStore: blobStore)
        visualCache.invalidatePath(item.blobRelativePath, blobStore: blobStore)
        visualCache.invalidatePath(item.linkIconRelativePath, blobStore: blobStore)
        visualCache.invalidatePath(item.linkImageRelativePath, blobStore: blobStore)
        if contentHashIndex[item.contentHash] == item.id {
            contentHashIndex.removeValue(forKey: item.contentHash)
        }
        foldedSearchByID.removeValue(forKey: item.id)
        searchDocumentsByID.removeValue(forKey: item.id)
        context.delete(item)
        clips.removeAll { $0.id == item.id }
        saveQuietly()
        notifyChange()
    }

    /// User removal, with a detached snapshot retained for bounded undo.
    @discardableResult
    func removeFromTab(_ item: ClipItem, tab: TimelineTab) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == item.id }) else { return false }
        removalError = nil
        expireRemovalUndo()
        let snapshot = item.removalSnapshot()
        let nextItems = Dictionary(uniqueKeysWithValues: pinboards.compactMap { board -> (UUID, UUID)? in
            guard let position = board.itemIDs.firstIndex(of: item.id),
                  let nextID = board.itemIDs.dropFirst(position + 1).first else { return nil }
            return (board.id, nextID)
        })
        let removal = Removal(snapshot: snapshot, tab: tab,
            nextID: index + 1 < clips.count ? clips[index + 1].id : nil,
            boardNextIDs: nextItems, expiresAt: Date().addingTimeInterval(30))
        removals.append(removal)
        updateRemovalProtection()
        switch tab {
        case .timeline:
            item.isHiddenFromTimeline = true
        case .pinned:
            let board = pinnedPinboard
            item.pinboardIDs.removeAll { $0 == board.id }
            board.itemIDs.removeAll { $0 == item.id }
        case .folder(let id):
            item.pinboardIDs.removeAll { $0 == id }
            pinboards.first { $0.id == id }?.itemIDs.removeAll { $0 == item.id }
        }
        let shouldDelete = item.isHiddenFromTimeline && item.pinboardIDs.isEmpty
        if shouldDelete { context.delete(item) }
        guard saveQuietly() else {
            removals.removeLast()
            updateRemovalProtection()
            context.rollback()
            refresh()
            removalError = L10n.tr("removal.saveFailed", default: "Could not save the change. Your history has been restored; try again.")
            return false
        }
        if shouldDelete { clips.removeAll { $0.id == snapshot.id } }
        if removals.count > 20 { removals.removeFirst(removals.count - 20) }
        rebuildIndexes()
        updateRemovalProtection()
        notifyChange()
        return true
    }

    func hideFromTimeline(_ item: ClipItem) {
        guard !item.isHiddenFromTimeline else { return }
        item.isHiddenFromTimeline = true
        item.updatedAt = Date()
        saveQuietly()
        notifyChange()
    }

    /// After leaving the last pinboard, a timeline-hidden clip has nowhere to live — delete it.
    private func purgeIfOrphaned(_ item: ClipItem) {
        guard item.pinboardIDs.isEmpty else { return }
        if item.isHiddenFromTimeline {
            delete(item)
        }
    }

    func thumbnailImage(for item: ClipItem) -> NSImage? {
        visualCache.image(at: item.thumbnailRelativePath, blobStore: blobStore)
    }

    /// Cache hit only — never blocks the main thread on disk IO.
    func cachedThumbnailImage(for item: ClipItem) -> NSImage? {
        visualCache.cachedImage(at: item.thumbnailRelativePath, blobStore: blobStore)
    }

    func loadThumbnailImage(for item: ClipItem) async -> NSImage? {
        await visualCache.loadImage(at: item.thumbnailRelativePath, blobStore: blobStore)
    }

    func loadPreviewImage(for item: ClipItem) async -> NSImage? {
        await visualCache.loadImage(at: item.blobRelativePath ?? item.thumbnailRelativePath,
                                    blobStore: blobStore, maxPixelSize: 1_600)
    }

    func fullImage(for item: ClipItem) -> NSImage? {
        visualCache.image(at: item.blobRelativePath, blobStore: blobStore)
    }

    func linkIconImage(for item: ClipItem) -> NSImage? {
        visualCache.image(at: item.linkIconRelativePath, blobStore: blobStore)
    }

    func cachedLinkPreviewImage(for item: ClipItem) -> NSImage? {
        visualCache.cachedImage(at: item.linkImageRelativePath, blobStore: blobStore)
            ?? visualCache.cachedImage(at: item.linkIconRelativePath, blobStore: blobStore)
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
        Task { @MainActor in
            await enrichLinkMetadata(for: id)
        }
    }

    /// Awaits OG/favicon fetch for a URL clip. Still runs when title is present but preview images are missing.
    @discardableResult
    func enrichLinkMetadata(for id: UUID) async -> Bool {
        guard let item = clips.first(where: { $0.id == id }) ?? fetchClip(id: id) else { return false }
        guard item.primaryType == .url else { return false }

        let needsTitle = item.linkTitle == nil || item.linkTitle?.isEmpty == true
        let needsIcon = item.linkIconRelativePath == nil
        let needsImage = item.linkImageRelativePath == nil
        guard needsTitle || needsIcon || needsImage else { return true }
        guard !enrichingIDs.contains(id) else {
            // Another enrich in flight — wait briefly for paths to appear.
            return await waitForLinkPreviewPaths(id: id, timeoutNanoseconds: 12_000_000_000)
        }

        let urlString = item.fileURLString ?? item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return false
        }

        enrichingIDs.insert(id)
        defer { enrichingIDs.remove(id) }

        let metadata = await linkMetadataService.metadata(for: url)
        let store = blobStore
        let paths = await Task.detached(priority: .utility) {
            let icon = needsIcon ? metadata.iconData.flatMap {
                try? store.storeThumbnail(fromImageData: $0, maxDimension: 128)?.path
            } : nil
            let image = needsImage ? metadata.imageData.flatMap {
                try? store.storeThumbnail(fromImageData: $0, maxDimension: 720)?.path
            } : nil
            return (icon, image)
        }.value
        guard let liveItem = clips.first(where: { $0.id == id }) ?? fetchClip(id: id) else {
            // The clip was deleted while metadata was in flight; discard only these new files.
            await Task.detached(priority: .utility) {
                for path in [paths.0, paths.1].compactMap({ $0 }) {
                    if let url = store.url(for: path) { try? FileManager.default.removeItem(at: url) }
                }
            }.value
            return false
        }

        var didUpdate = false
        if needsTitle, let title = metadata.title, !title.isEmpty {
            liveItem.linkTitle = title
            if liveItem.title == liveItem.plainText || liveItem.title.count > 80 {
                liveItem.title = String(title.prefix(80))
            }
            didUpdate = true
        }
        if let icon = paths.0 { liveItem.linkIconRelativePath = icon; didUpdate = true }
        if let image = paths.1 { liveItem.linkImageRelativePath = image; didUpdate = true }

        if didUpdate {
            liveItem.updatedAt = Date()
            visualCache.invalidate(clipID: id)
            foldedSearchByID.removeValue(forKey: id)
            saveQuietly()
            notifyChange(contentID: id)
        }

        return liveItem.linkImageRelativePath != nil || liveItem.linkIconRelativePath != nil
    }

    /// Used by Agent API render: fetch missing link previews, then warm the image cache.
    func awaitMissingLinkPreviews() async {
        let ids = clips
            .filter { $0.primaryType == .url }
            .filter { $0.linkImageRelativePath == nil && $0.linkIconRelativePath == nil }
            .map(\.id)

        // Sequential is fine (few cards); avoids TaskGroup + MainActor isolation issues.
        for id in ids {
            _ = await enrichLinkMetadata(for: id)
        }

        for item in clips where item.primaryType == .url {
            _ = await loadLinkPreviewImage(for: item)
        }
    }

    private func waitForLinkPreviewPaths(id: UUID, timeoutNanoseconds: UInt64) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let item = clips.first(where: { $0.id == id }),
               item.linkImageRelativePath != nil || item.linkIconRelativePath != nil {
                return true
            }
            if !enrichingIDs.contains(id) {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if let item = clips.first(where: { $0.id == id }) {
            return item.linkImageRelativePath != nil || item.linkIconRelativePath != nil
        }
        return false
    }

    func clearHistory(keepPinned: Bool = true) {
        _ = deleteReviewedClips(ids: Set(clips.map(\.id)), keepSaved: keepPinned)
    }

    static let pinnedBoardName = "Pinned"
    private static let legacyFavoritesName = "Favorites"
    static let maxCustomFolders = 3

    /// System board backing the Pinned tab. Created on demand if missing.
    var pinnedPinboard: Pinboard {
        ensurePinnedPinboard()
    }

    /// User-created folders (everything except the system Pinned board).
    var customFolders: [Pinboard] {
        pinboards.filter { $0.name != Self.pinnedBoardName }
    }

    var canCreateCustomFolder: Bool {
        customFolders.count < Self.maxCustomFolders
    }

    func isSystemPinnedBoard(_ pinboard: Pinboard) -> Bool {
        pinboard.name == Self.pinnedBoardName
    }

    func isPinned(_ item: ClipItem) -> Bool {
        item.pinboardIDs.contains(pinnedPinboard.id)
    }

    @discardableResult
    func createPinboard(name: String, colorHex: String = "#6C7BFF") -> Pinboard {
        let pinboard = Pinboard(name: name, colorHex: colorHex)
        context.insert(pinboard)
        saveQuietly()
        pinboards.append(pinboard)
        notifyChange()
        return pinboard
    }

    /// Creates a custom folder tab. Returns nil if at the limit, name is empty, or reserved.
    @discardableResult
    func createCustomFolder(name: String, colorHex: String = "#6C7BFF") -> Pinboard? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canCreateCustomFolder else { return nil }
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.caseInsensitiveCompare(Self.pinnedBoardName) != .orderedSame else { return nil }
        return createPinboard(name: trimmed, colorHex: colorHex)
    }

    func renamePinboard(_ pinboard: Pinboard, name: String) {
        pinboard.name = name
        pinboard.updatedAt = Date()
        saveQuietly()
        notifyChange()
    }

    /// Renames a custom folder. Refuses the system Pinned board and reserved names.
    @discardableResult
    func renameCustomFolder(_ pinboard: Pinboard, name: String) -> Bool {
        guard !isSystemPinnedBoard(pinboard) else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.caseInsensitiveCompare(Self.pinnedBoardName) != .orderedSame else { return false }
        renamePinboard(pinboard, name: trimmed)
        return true
    }

    func deletePinboard(_ pinboard: Pinboard) {
        for item in clips where item.pinboardIDs.contains(pinboard.id) {
            item.pinboardIDs.removeAll { $0 == pinboard.id }
        }
        context.delete(pinboard)
        pinboards.removeAll { $0.id == pinboard.id }
        saveQuietly()
        notifyChange()
    }

    /// Deletes a custom folder. Refuses the system Pinned board.
    @discardableResult
    func deleteCustomFolder(_ pinboard: Pinboard) -> Bool {
        guard !isSystemPinnedBoard(pinboard) else { return false }
        deletePinboard(pinboard)
        return true
    }

    func pin(_ item: ClipItem, to pinboard: Pinboard) {
        if !item.pinboardIDs.contains(pinboard.id) {
            item.pinboardIDs.append(pinboard.id)
        }
        if !pinboard.itemIDs.contains(item.id) {
            pinboard.itemIDs.insert(item.id, at: 0)
        }
        saveQuietly()
        notifyChange()
    }

    /// Pins to the system Pinned board so the item survives history pruning.
    func pinToPinnedBoard(_ item: ClipItem) {
        pin(item, to: pinnedPinboard)
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
        notifyChange()
        purgeIfOrphaned(item)
    }

    /// Removes the item from the system Pinned board only (leaves custom folders alone).
    func unpinFromPinnedBoard(_ item: ClipItem) {
        unpin(item, from: pinnedPinboard)
    }

    func pruneHistory(force: Bool = true) {
        expireRemovalUndo()
        let undoIDs = Set(removals.map { $0.snapshot.id })
        var didDelete = false
        if let cutoff = settings.keepHistory.cutoffDate {
            let expired = clips.filter { $0.createdAt < cutoff && $0.pinboardIDs.isEmpty && !undoIDs.contains($0.id) }
            for item in expired {
                removeFromIndexes(item)
                context.delete(item)
                didDelete = true
            }
            if !expired.isEmpty {
                let expiredIDs = Set(expired.map(\.id))
                clips.removeAll { expiredIDs.contains($0.id) }
            }
        }

        let unpinned = clips.filter { $0.pinboardIDs.isEmpty && !undoIDs.contains($0.id) }
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
            notifyChange()
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
        searchDocumentsByID.removeValue(forKey: item.id)
        visualCache.invalidate(clipID: item.id)
        visualCache.invalidatePath(item.thumbnailRelativePath, blobStore: blobStore)
        visualCache.invalidatePath(item.blobRelativePath, blobStore: blobStore)
        visualCache.invalidatePath(item.linkIconRelativePath, blobStore: blobStore)
        visualCache.invalidatePath(item.linkImageRelativePath, blobStore: blobStore)
    }

    private func rebuildIndexes() {
        contentHashIndex.removeAll(keepingCapacity: true)
        foldedSearchByID.removeAll(keepingCapacity: true)
        searchDocumentsByID.removeAll(keepingCapacity: true)
        for item in clips {
            contentHashIndex[item.contentHash] = item.id
        }
    }

    private func fetchClip(id: UUID) -> ClipItem? {
        let descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func createDefaultPinboards() {
        context.insert(Pinboard(name: Self.pinnedBoardName, colorHex: "#6C7BFF"))
        saveQuietly()
        refresh()
    }

    /// Renames legacy "Favorites" → "Pinned" when upgrading existing libraries.
    private func migratePinnedPinboardIfNeeded() {
        let hasPinned = pinboards.contains { $0.name == Self.pinnedBoardName }
        guard let favorites = pinboards.first(where: { $0.name == Self.legacyFavoritesName }) else {
            return
        }
        guard !hasPinned else { return }
        favorites.name = Self.pinnedBoardName
        favorites.updatedAt = Date()
        saveQuietly()
        notifyChange()
    }

    @discardableResult
    private func ensurePinnedPinboard() -> Pinboard {
        if let board = pinboards.first(where: { $0.name == Self.pinnedBoardName }) {
            return board
        }
        return createPinboard(name: Self.pinnedBoardName, colorHex: "#6C7BFF")
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

    /// One-shot: after adding `lastUsedAt`, seed it from `createdAt` so existing
    /// libraries keep a stable timeline order (matches prior createdAt sort).
    private func backfillLastUsedAtIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.didBackfillLastUsedAtKey) else { return }
        for item in clips {
            item.lastUsedAt = item.createdAt
        }
        if saveQuietly() {
            UserDefaults.standard.set(true, forKey: Self.didBackfillLastUsedAtKey)
            clips.sort { $0.lastUsedAt > $1.lastUsedAt }
            notifyChange()
            NSLog("PasteIt: backfilled lastUsedAt for \(clips.count) clips")
        } else {
            NSLog("PasteIt: failed to backfill lastUsedAt; will retry next launch")
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
