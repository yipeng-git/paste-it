import Combine
import Foundation
import PasteItCore

enum TimelineTab: Equatable, Hashable, Identifiable, Sendable {
    case timeline
    case pinned
    case folder(UUID)

    /// Fixed tabs that always appear (Default + Pinned).
    static let fixedTabs: [TimelineTab] = [.timeline, .pinned]

    var id: String {
        switch self {
        case .timeline: return "timeline"
        case .pinned: return "pinned"
        case .folder(let id): return "folder-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .timeline: return L10n.tr("tab.default", default: "Default")
        case .pinned: return L10n.tr("tab.pinned", default: "Pinned")
        case .folder: return L10n.tr("tab.folder", default: "Folder")
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: return "clock"
        case .pinned: return "pin.fill"
        case .folder: return "folder"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    /// Live search draft. Not `@Published`: keystrokes must not rebuild the card strip.
    var query: String = ""
    /// Bumped when `query` is reset from outside the field (clear, hide, agent).
    @Published var searchFieldSeed: Int = 0
    @Published private(set) var visibleClips: [ClipItem] = [] {
        didSet { visibleClipsVersion &+= 1 }
    }
    private(set) var visibleClipsVersion: UInt64 = 0
    @Published var selectedClipID: UUID?
    /// Multi-select set for ⌘-click. Anchor `selectedClipID` is always in this set when non-empty.
    @Published private(set) var selectedClipIDs: [UUID] = []
    @Published var selectedTab: TimelineTab = .timeline {
        didSet {
            guard selectedTab != oldValue, !isBatchUpdatingFilters else { return }
            beginTabSwitch()
        }
    }
    @Published var selectedFilter: FilterCategory = .all {
        didSet {
            guard selectedFilter != oldValue, !isBatchUpdatingFilters else { return }
            rebuildVisibleClips()
        }
    }
    @Published var selectedSourceApp: String? {
        didSet {
            guard selectedSourceApp != oldValue, !isBatchUpdatingFilters else { return }
            rebuildVisibleClips()
        }
    }
    @Published var statusMessage: String?
    let removalFeedback = RemovalFeedback()
    /// Bumped when the timeline wants the search field to take focus (⌘F).
    @Published var searchFocusRequest: Int = 0
    /// Bumped when the timeline should resign search focus (panel show / Esc).
    @Published var searchBlurRequest: Int = 0
    /// Bumped when the timeline should scroll back to the first card (panel show / promote).
    @Published var scrollToStartRequest: Int = 0
    /// When set, the timeline shows the space-bar quick preview for this item.
    @Published var previewClip: ClipItem?
    /// Bumped to ask the open preview bubble to enter text-editing mode.
    @Published var previewEditRequest: Int = 0

    let settings: AppSettings
    let historyStore: HistoryStore
    let searchService: SearchService

    weak var panelController: TimelinePanelController?
    var pasteStackController: PasteStackController?

    @Published private var debouncedQuery: String = ""
    private var searchDebounceTask: Task<Void, Never>?
    /// Last tab applied to the visible result snapshot.
    private var lastAppliedTab: TimelineTab = .timeline
    private var clipsObservation: AnyCancellable?
    private var isBatchUpdatingFilters = false
    /// Hover Copy / ⌘C while browsing: persist recency after the panel closes.
    private var pendingPromoteAfterHide: UUID?
    /// Per-tab source lists (timeline / pinned / folders) — rebuilt once per history change.
    private var tabSourceCache: [String: [ClipItem]] = [:]
    /// Per-tab filtered results under the current query / filter / source-app key.
    private var tabVisibleCache: [String: [ClipItem]] = [:]
    private var tabVisibleCacheFilterKey: String = ""
    private var visibleClipsRebuildTask: Task<Void, Never>?
    private let searchIndex = ClipSearchIndex()
    private var searchGeneration = 0

    init(
        settings: AppSettings,
        historyStore: HistoryStore,
        searchService: SearchService
    ) {
        self.settings = settings
        self.historyStore = historyStore
        self.searchService = searchService

        clipsObservation = historyStore.changes.sink { [weak self] change in
            guard let self else { return }
            if change.collectionChanged {
                self.invalidateTabCaches()
                self.rebuildVisibleClips(preserveOrder: self.panelController?.isVisible == true)
            } else if !self.debouncedQuery.isEmpty || self.selectedFilter != .all {
                self.tabVisibleCache.removeAll(keepingCapacity: true)
                self.rebuildVisibleClips(preserveOrder: self.panelController?.isVisible == true)
            }
            // SwiftData tracks card content directly when only metadata/text changed.
        }
        rebuildVisibleClips()
    }

    var selectedClip: ClipItem? {
        guard let selectedClipID else { return visibleClips.first }
        return visibleClips.first { $0.id == selectedClipID }
    }

    var isMultiSelecting: Bool {
        selectedCount > 1
    }

    var selectedCount: Int {
        var ids = Set(selectedClipIDs)
        if let selectedClipID { ids.insert(selectedClipID) }
        return ids.count
    }

    /// Selected clips in left-to-right `visibleClips` order.
    /// Always includes the anchor `selectedClipID` so a default-highlighted card
    /// is not left out when multi-select expands.
    var orderedSelectedClips: [ClipItem] {
        var ids = Set(selectedClipIDs)
        if let selectedClipID {
            ids.insert(selectedClipID)
        }
        guard !ids.isEmpty else { return [] }
        return visibleClips.filter { ids.contains($0.id) }
    }

    /// Highlight / filter string currently applied to cards (lags the field by debounce).
    var searchHighlight: String { debouncedQuery }

    func applySearchTyping(_ next: String) {
        guard query != next else { return }
        query = next
        scheduleSearchDebounce()
    }

    func clearSearch() {
        applySearchTyping("")
        searchFieldSeed += 1
    }

    func setQueryFromExternal(_ next: String) {
        query = next
        searchFieldSeed += 1
        scheduleSearchDebounce()
    }

    /// Await the current request when an ephemeral renderer or integration test needs a settled snapshot.
    func awaitSearchResults() async {
        await searchDebounceTask?.value
        await visibleClipsRebuildTask?.value
    }

    /// Cheap open path: the list is already Default/All. Scroll was reset on the previous hide.
    func isReadyForInstantShow() -> Bool {
        query.isEmpty && debouncedQuery.isEmpty && selectedTab == .timeline && selectedSourceApp == nil
    }

    /// Warm unfiltered membership lists without scheduling competing background searches.
    func warmTabCaches() {
        // Membership caches are cheap and shared with the active tab. Filtered
        // searches are performed on demand so warming cannot compete with typing.
        guard debouncedQuery.isEmpty, selectedFilter == .all, selectedSourceApp == nil else { return }
        ensureTabSourceCache()
    }

    /// `historyStore.add` lands before Combine updates `visibleClips`. Call after a
    /// clipboard flush so the panel never opens with the old first card still selected.
    func absorbNewestClipBeforePanelShow() {
        if selectedTab == .timeline,
           let newest = historyStore.clips.first,
           visibleClips.first?.id != newest.id,
           belongsInCurrentVisibleList(newest) {
            invalidateTabCaches()
            visibleClips.removeAll { $0.id == newest.id }
            visibleClips.insert(newest, at: 0)
        }
        selectFirst(scroll: false)
    }

    /// After the panel is ordered out: restore Default/All, park the viewport at the first card,
    /// and apply any copy-while-browsing promote so the next open is already warm.
    func prepareForNextPanelShow() {
        if let id = pendingPromoteAfterHide {
            pendingPromoteAfterHide = nil
            if let item = historyStore.clips.first(where: { $0.id == id }) {
                historyStore.promoteToFront(item)
            }
        }
        resetFiltersForPanelShow()
    }

    /// Copy while the timeline stays open: pasteboard only. Don't shuffle the map.
    func notePromoteAfterHide(_ item: ClipItem) {
        pendingPromoteAfterHide = item.id
    }

    /// Pin on Default keeps the card where it is (membership only). Unpin / hide on the
    /// current board removes just that row immediately; the coalesced history event confirms membership.
    func togglePinned(_ item: ClipItem) {
        if historyStore.isPinned(item) {
            guard historyStore.removeFromTab(item, tab: .pinned) else { return }
            showRemovalFeedback(from: .pinned)
            if selectedTab == .pinned {
                invalidateTabCaches()
                visibleClips.removeAll { $0.id == item.id }
                pruneSelectionToVisibleClips()
            }
        } else {
            historyStore.pinToPinnedBoard(item)
            if selectedTab == .pinned, !visibleClips.contains(where: { $0.id == item.id }) {
                invalidateTabCaches()
                visibleClips.insert(item, at: 0)
            }
        }
    }

    func pin(_ item: ClipItem, to folder: Pinboard) {
        historyStore.pin(item, to: folder)
    }

    func unpin(_ item: ClipItem, from folder: Pinboard) {
        guard historyStore.removeFromTab(item, tab: .folder(folder.id)) else { return }
        showRemovalFeedback(from: .folder(folder.id))
        if case .folder(let id) = selectedTab, id == folder.id {
            invalidateTabCaches()
            visibleClips.removeAll { $0.id == item.id }
            pruneSelectionToVisibleClips()
        }
    }

    func removeClipFromCurrentTab(_ item: ClipItem) {
        let tab = selectedTab
        let staysSaved = tab == .timeline && !item.pinboardIDs.isEmpty
        guard historyStore.removeFromTab(item, tab: tab) else { return }
        showRemovalFeedback(from: tab, staysSaved: staysSaved)
        invalidateTabCaches()
        visibleClips.removeAll { $0.id == item.id }
        pruneSelectionToVisibleClips()
    }

    func removalTitle(for tab: TimelineTab) -> String {
        switch tab {
        case .timeline: return L10n.tr("removal.history", default: "Remove from History")
        case .pinned: return L10n.tr("timeline.unpin", default: "Unpin")
        case .folder(let id):
            let name = historyStore.customFolders.first { $0.id == id }?.name ?? tab.title
            return L10n.tr("removal.namedFolder", default: "Remove from “%@”", name)
        }
    }

    private func showRemovalFeedback(from tab: TimelineTab, staysSaved: Bool = false) {
        let message: String
        switch tab {
        case .timeline:
            message = staysSaved
                ? L10n.tr("removal.stillSaved", default: "Removed from History; still saved in Pinned or folders")
                : L10n.tr("removal.removedHistory", default: "Removed from History")
        case .pinned:
            message = L10n.tr("removal.unpinned", default: "Unpinned")
        case .folder(let id):
            let name = historyStore.customFolders.first { $0.id == id }?.name ?? tab.title
            message = L10n.tr("removal.removedFolder", default: "Removed from “%@”", name)
        }
        removalFeedback.show(message, removalID: historyStore.latestRemovalID)
    }

    func undoLastRemoval(expectedID: UUID? = nil) {
        guard let restored = historyStore.undoLastRemoval(expectedID: expectedID) else { return }
        removalFeedback.show(L10n.tr("removal.restored", default: "Removal undone"))
        selectedTab = restored.tab
        invalidateTabCaches()
        rebuildVisibleClips()
        Task { @MainActor in
            await awaitSearchResults()
            if visibleClips.contains(where: { $0.id == restored.item.id }) {
                selectOnly(restored.item.id)
            }
        }
    }

    func resetFiltersForPanelShow() {
        isBatchUpdatingFilters = true
        searchDebounceTask?.cancel()
        query = ""
        debouncedQuery = ""
        selectedTab = .timeline
        selectedSourceApp = nil
        isBatchUpdatingFilters = false
        searchFieldSeed += 1
        rebuildVisibleClips()
        // Always start from the first card — don't preserve prior selection/scroll.
        selectFirst(scroll: true)
    }

    /// Applies a type filter and strips conflicting `type:` tokens from the query.
    func setFilter(_ filter: FilterCategory) {
        dismissPreview()
        isBatchUpdatingFilters = true
        selectedFilter = filter
        let stripped = SearchQuery.strippingTypeTokens(from: query)
        if stripped != query {
            query = stripped
            debouncedQuery = stripped
            searchFieldSeed += 1
        }
        isBatchUpdatingFilters = false
        rebuildVisibleClips()
        selectFirst(scroll: true)
    }

    /// Per-type counts under the current tab / query / source-app filters (single pass).
    func countsMatchingAllFilters() async -> [FilterCategory: Int]? {
        let generation = searchGeneration
        let documents = historyStore.searchDocuments(for: sourceClipsForCurrentTab())
        let counts = try? await searchIndex.counts(documents, query: debouncedQuery, sourceApp: selectedSourceApp)
        guard !Task.isCancelled, generation == searchGeneration else { return nil }
        return counts
    }

    func selectOnly(_ id: UUID) {
        if selectedClipID != id { selectedClipID = id }
        if selectedClipIDs != [id] { selectedClipIDs = [id] }
    }

    func selectClipsForRecovery(_ ids: [UUID]) {
        selectedClipID = ids.first
        selectedClipIDs = ids
    }

    /// Single-click a timeline card while a Space preview may be open.
    /// Same card → dismiss preview; other card → select (preview retargets via selection sync).
    func handlePreviewAwareCardClick(_ id: UUID) {
        if previewClip?.id == id {
            dismissPreview()
            return
        }
        selectOnly(id)
    }

    func dismissPreview() {
        guard previewClip != nil else { return }
        previewClip = nil
    }

    /// Keep an open preview bound to the current selection (Quick Look retarget), or close if none.
    func syncPreviewToSelection() {
        guard previewClip != nil else { return }
        if let selectedClip {
            if previewClip?.id != selectedClip.id {
                previewClip = selectedClip
            }
        } else {
            dismissPreview()
        }
    }

    func toggleMultiSelect(_ id: UUID) {
        // Keep the current single-selection anchor inside the multi-set before
        // expanding, so the default-highlighted card stays selected.
        if let anchor = selectedClipID,
           !selectedClipIDs.contains(anchor) {
            selectedClipIDs.insert(anchor, at: 0)
        }

        if let index = selectedClipIDs.firstIndex(of: id) {
            selectedClipIDs.remove(at: index)
            if selectedClipIDs.isEmpty {
                selectOnly(id)
                return
            }
            if selectedClipID == id {
                selectedClipID = selectedClipIDs.last
            }
        } else {
            selectedClipIDs.append(id)
            selectedClipID = id
        }
    }

    /// After multi paste/copy: keep only the anchor as a single selection.
    func clearMultiSelectKeepingAnchor() {
        if let selectedClipID {
            selectedClipIDs = [selectedClipID]
        } else if let first = visibleClips.first?.id {
            selectOnly(first)
        } else {
            selectedClipIDs = []
        }
    }

    func selectFirstIfNeeded() {
        pruneSelectionToVisibleClips()
        if selectedClipID == nil || !visibleClips.contains(where: { $0.id == selectedClipID }) {
            selectFirst()
        }
    }

    func selectFirst(scroll: Bool = false) {
        if let id = visibleClips.first?.id {
            selectOnly(id)
        } else {
            selectedClipID = nil
            selectedClipIDs = []
        }
        if scroll {
            scrollToStartRequest += 1
        }
    }

    /// Stages an accessed clip to the front of history and keeps selection/scroll in sync.
    func promoteAccessedClip(_ item: ClipItem, scroll: Bool = true) {
        historyStore.promoteToFront(item)
        // Panel already gone: persist order only. Next `show` rebuilds `visibleClips`.
        if let panelController, !panelController.isVisible {
            return
        }
        rebuildVisibleClips()
        selectOnly(item.id)
        if scroll {
            scrollToStartRequest += 1
        }
    }

    private func pruneSelectionToVisibleClips() {
        let visibleIDs = Set(visibleClips.map(\.id))
        selectedClipIDs = selectedClipIDs.filter { visibleIDs.contains($0) }
        if let selectedClipID, !visibleIDs.contains(selectedClipID) {
            self.selectedClipID = selectedClipIDs.last ?? visibleClips.first?.id
        }
        if selectedClipIDs.isEmpty, let selectedClipID, visibleIDs.contains(selectedClipID) {
            selectedClipIDs = [selectedClipID]
        }
    }

    /// Opens (or focuses) the Space preview bubble and enters text editing when supported.
    @discardableResult
    func beginEditingClip(_ clip: ClipItem) -> Bool {
        guard clip.supportsBubbleEditing else { return false }
        selectOnly(clip.id)
        previewClip = clip
        // Defer so ClipQuickPreview is mounted / updated before it observes the bump.
        DispatchQueue.main.async {
            self.previewEditRequest += 1
        }
        return true
    }

    @discardableResult
    func beginEditingSelectedClip() -> Bool {
        guard let clip = selectedClip else { return false }
        return beginEditingClip(clip)
    }

    /// Space-bar "Quick Look" toggle: opens a full-fidelity preview of the selected
    /// clip, or closes it if one is already showing.
    func togglePreviewForSelectedClip() {
        if previewClip != nil {
            dismissPreview()
        } else {
            previewClip = selectedClip
        }
    }

    func setStatus(_ message: String) {
        statusMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        let next = query
        // Empty query should apply immediately so clearing feels snappy.
        if next.isEmpty {
            debouncedQuery = ""
            rebuildVisibleClips()
            return
        }
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            debouncedQuery = next
            rebuildVisibleClips()
        }
    }

    private func belongsInCurrentVisibleList(_ item: ClipItem) -> Bool {
        switch selectedTab {
        case .timeline:
            guard !item.isHiddenFromTimeline else { return false }
        case .pinned:
            guard item.pinboardIDs.contains(historyStore.pinnedPinboard.id) else { return false }
        case .folder(let id):
            guard item.pinboardIDs.contains(id) else { return false }
        }
        return searchService.search(
            clips: [item],
            query: debouncedQuery,
            selectedFilter: selectedFilter,
            sourceApp: selectedSourceApp,
            pinboardID: nil,
            foldedHaystack: { [historyStore] candidate in
                historyStore.foldedSearchText(for: candidate)
            }
        ).contains { $0.id == item.id }
    }

    private func rebuildVisibleClips(tabChanged: Bool = false, preserveOrder: Bool = false) {
        visibleClipsRebuildTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        if case .folder(let id) = selectedTab,
           !historyStore.customFolders.contains(where: { $0.id == id }) {
            isBatchUpdatingFilters = true
            selectedTab = .timeline
            isBatchUpdatingFilters = false
        }
        let didChangeTab = tabChanged || selectedTab != lastAppliedTab
        let tab = selectedTab
        let key = visibleCacheFilterKey
        let query = debouncedQuery
        lastAppliedTab = tab
        if key != tabVisibleCacheFilterKey {
            tabVisibleCache.removeAll(keepingCapacity: true)
            tabVisibleCacheFilterKey = key
        }
        if let cached = tabVisibleCache[tab.id] {
            applyResults(cached, tabChanged: didChangeTab, preserveOrder: preserveOrder)
            return
        }
        let source = sourceClipsForCurrentTab()
        if query.isEmpty, selectedFilter == .all, selectedSourceApp == nil {
            tabVisibleCache[tab.id] = source
            applyResults(source, tabChanged: didChangeTab, preserveOrder: preserveOrder)
            return
        }
        let documents = historyStore.searchDocuments(for: source)
        let filter = selectedFilter
        let sourceApp = selectedSourceApp
        visibleClipsRebuildTask = Task { @MainActor in
            guard let ids = try? await searchIndex.search(documents, query: query, filter: filter, sourceApp: sourceApp),
                  !Task.isCancelled, generation == searchGeneration,
                  tab == selectedTab, key == visibleCacheFilterKey else { return }
            let matches = Set(ids)
            let result = source.filter { matches.contains($0.id) }
            tabVisibleCache[tab.id] = result
            applyResults(result, tabChanged: didChangeTab, preserveOrder: preserveOrder)
            Analytics.notePanelSearch(resultCount: result.count)
        }
    }

    private func applyResults(_ clips: [ClipItem], tabChanged: Bool, preserveOrder: Bool) {
        let result: [ClipItem]
        if preserveOrder, !tabChanged {
            // Keep the browsing map stable, while honoring removals and edited matches.
            let valid = Set(clips.map(\.id))
            let existing = Set(visibleClips.map(\.id))
            result = clips.filter { !existing.contains($0.id) }
                + visibleClips.filter { valid.contains($0.id) }
        } else {
            result = clips
        }
        if !visibleClips.elementsEqual(result, by: { $0.id == $1.id }) {
            visibleClips = result
        }
        finishVisibleClipsRebuild(tabChanged: tabChanged)
    }

    private func beginTabSwitch() {
        if panelController?.isVisible == true { scrollToStartRequest += 1 }
        visibleClips = []
        selectedClipID = nil
        selectedClipIDs = []
        rebuildVisibleClips(tabChanged: true)
    }

    private func finishVisibleClipsRebuild(tabChanged: Bool) {
        if panelController?.isVisible == true {
            if tabChanged {
                selectFirst(scroll: false)
            } else {
                selectFirstIfNeeded()
            }
        } else {
            // Hidden ingest prepends a card; keep selection on the new first
            // so the next ⇧⌘V doesn't highlight the previous first (now second).
            selectFirst(scroll: false)
        }
    }

    private var visibleCacheFilterKey: String {
        "\(selectedFilter.rawValue)|\(debouncedQuery)|\(selectedSourceApp ?? "")"
    }

    private func invalidateTabCaches() {
        tabSourceCache.removeAll(keepingCapacity: true)
        tabVisibleCache.removeAll(keepingCapacity: true)
        tabVisibleCacheFilterKey = ""
    }

    private func ensureTabSourceCache() {
        guard tabSourceCache.isEmpty else { return }
        let pinnedID = historyStore.pinnedPinboard.id
        for item in historyStore.clips {
            if !item.isHiddenFromTimeline {
                tabSourceCache[TimelineTab.timeline.id, default: []].append(item)
            }
            for boardID in item.pinboardIDs {
                if boardID == pinnedID {
                    tabSourceCache[TimelineTab.pinned.id, default: []].append(item)
                }
                tabSourceCache[TimelineTab.folder(boardID).id, default: []].append(item)
            }
        }
    }

    private func sourceClipsForCurrentTab() -> [ClipItem] {
        ensureTabSourceCache()
        return tabSourceCache[selectedTab.id] ?? []
    }
}
