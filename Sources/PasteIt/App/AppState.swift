import Combine
import Foundation
import PasteItCore

enum TimelineTab: Equatable, Hashable, Identifiable {
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
        case .timeline: return "Default"
        case .pinned: return "Pinned"
        case .folder: return "Folder"
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
    @Published private(set) var visibleClips: [ClipItem] = []
    @Published var selectedClipID: UUID?
    /// Multi-select set for ⌘-click. Anchor `selectedClipID` is always in this set when non-empty.
    @Published private(set) var selectedClipIDs: [UUID] = []
    @Published var selectedTab: TimelineTab = .timeline {
        didSet {
            guard selectedTab != oldValue, !isBatchUpdatingFilters else { return }
            rebuildVisibleClips()
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

    private var debouncedQuery: String = ""
    private var searchDebounceTask: Task<Void, Never>?
    /// Last query applied to `visibleClips`, used to narrow instead of a full scan.
    private var lastAppliedQuery: String = ""
    private var lastAppliedTab: TimelineTab = .timeline
    private var lastAppliedFilter: FilterCategory = .all
    private var lastAppliedSourceApp: String?
    private var clipsObservation: AnyCancellable?
    private var isBatchUpdatingFilters = false
    /// Pin / delete / deferred promote already patched `visibleClips` — skip the extra search.
    private var skipNextHistoryRebuild = false
    /// Hover Copy / ⌘C while browsing: persist recency after the panel closes.
    private var pendingPromoteAfterHide: UUID?

    init(
        settings: AppSettings,
        historyStore: HistoryStore,
        searchService: SearchService
    ) {
        self.settings = settings
        self.historyStore = historyStore
        self.searchService = searchService

        clipsObservation = historyStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Defer so we read the updated `clips` array after the mutation lands.
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.skipNextHistoryRebuild {
                        self.skipNextHistoryRebuild = false
                        return
                    }
                    if self.applyIncrementalHistoryUpdateIfPossible() {
                        return
                    }
                    self.rebuildVisibleClips()
                }
            }
        rebuildVisibleClips()
    }

    var selectedClip: ClipItem? {
        guard let selectedClipID else { return visibleClips.first }
        return visibleClips.first { $0.id == selectedClipID }
    }

    var isMultiSelecting: Bool {
        orderedSelectedClips.count > 1
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

    /// Cheap open path: the list is already Default/All. Scroll was reset on the previous hide.
    func isReadyForInstantShow() -> Bool {
        query.isEmpty && debouncedQuery.isEmpty && selectedTab == .timeline && selectedSourceApp == nil
    }

    /// `historyStore.add` lands before Combine updates `visibleClips`. Call after a
    /// clipboard flush so the panel never opens with the old first card still selected.
    func absorbNewestClipBeforePanelShow() {
        if selectedTab == .timeline,
           let newest = historyStore.clips.first,
           visibleClips.first?.id != newest.id,
           belongsInCurrentVisibleList(newest) {
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
                skipNextHistoryRebuild = true
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
    /// current board removes just that row. Never a full search rebuild.
    func togglePinned(_ item: ClipItem) {
        skipNextHistoryRebuild = true
        if historyStore.isPinned(item) {
            historyStore.unpinFromPinnedBoard(item)
            if selectedTab == .pinned {
                visibleClips.removeAll { $0.id == item.id }
                pruneSelectionToVisibleClips()
            }
        } else {
            historyStore.pinToPinnedBoard(item)
            if selectedTab == .pinned, !visibleClips.contains(where: { $0.id == item.id }) {
                visibleClips.insert(item, at: 0)
            }
        }
    }

    func pin(_ item: ClipItem, to folder: Pinboard) {
        skipNextHistoryRebuild = true
        historyStore.pin(item, to: folder)
    }

    func unpin(_ item: ClipItem, from folder: Pinboard) {
        skipNextHistoryRebuild = true
        historyStore.unpin(item, from: folder)
        if case .folder(let id) = selectedTab, id == folder.id {
            visibleClips.removeAll { $0.id == item.id }
            pruneSelectionToVisibleClips()
        }
    }

    func removeClipFromCurrentTab(_ item: ClipItem) {
        skipNextHistoryRebuild = true
        historyStore.removeFromTab(item, tab: selectedTab)
        visibleClips.removeAll { $0.id == item.id }
        pruneSelectionToVisibleClips()
    }

    func resetFiltersForPanelShow() {
        isBatchUpdatingFilters = true
        searchDebounceTask?.cancel()
        query = ""
        debouncedQuery = ""
        lastAppliedQuery = ""
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
    func countsMatchingAllFilters() -> [FilterCategory: Int] {
        searchService.countsByFilter(
            clips: sourceClipsForCurrentTab(),
            query: debouncedQuery,
            sourceApp: selectedSourceApp,
            pinboardID: nil,
            foldedHaystack: { [historyStore] item in
                historyStore.foldedSearchText(for: item)
            }
        )
    }

    func selectOnly(_ id: UUID) {
        selectedClipID = id
        selectedClipIDs = [id]
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
            Analytics.notePanelSearch(resultCount: visibleClips.count)
        }
    }

    /// While the panel is open, treat the timeline as a map: a brand-new clipboard
    /// item is prepended on the left; existing rows keep identity and scroll.
    /// Duplicate promote / pin timestamp bumps do not reshuffle. Returns `false`
    /// when the change is too large for a local patch (search, hidden panel, …).
    private func applyIncrementalHistoryUpdateIfPossible() -> Bool {
        guard panelController?.isVisible == true else { return false }

        switch selectedTab {
        case .timeline:
            break
        case .pinned, .folder:
            // New copies land on Default, not on Pinned / folders.
            return true
        }

        guard let newest = historyStore.clips.first else { return false }

        if visibleClips.first?.id == newest.id {
            return true
        }

        if visibleClips.contains(where: { $0.id == newest.id }) {
            // History moved an existing clip to the front (duplicate). Leave the map still.
            return true
        }

        if belongsInCurrentVisibleList(newest) {
            visibleClips.insert(newest, at: 0)
        }
        return true
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

    private func rebuildVisibleClips() {
        if case .folder(let id) = selectedTab,
           !historyStore.customFolders.contains(where: { $0.id == id }) {
            isBatchUpdatingFilters = true
            selectedTab = .timeline
            isBatchUpdatingFilters = false
        }

        let canNarrow = !debouncedQuery.isEmpty
            && !lastAppliedQuery.isEmpty
            && debouncedQuery.hasPrefix(lastAppliedQuery)
            && selectedTab == lastAppliedTab
            && selectedFilter == lastAppliedFilter
            && selectedSourceApp == lastAppliedSourceApp
            && !visibleClips.isEmpty
        let source = canNarrow ? visibleClips : sourceClipsForCurrentTab()
        visibleClips = searchService.search(
            clips: source,
            query: debouncedQuery,
            selectedFilter: selectedFilter,
            sourceApp: selectedSourceApp,
            pinboardID: nil,
            foldedHaystack: { [historyStore] item in
                historyStore.foldedSearchText(for: item)
            }
        )
        lastAppliedQuery = debouncedQuery
        lastAppliedTab = selectedTab
        lastAppliedFilter = selectedFilter
        lastAppliedSourceApp = selectedSourceApp
        if panelController?.isVisible == true {
            selectFirstIfNeeded()
        } else {
            // Hidden ingest prepends a card; keep selection on the new first
            // so the next ⇧⌘V doesn't highlight the previous first (now second).
            selectFirst(scroll: false)
        }
    }

    private func sourceClipsForCurrentTab() -> [ClipItem] {
        switch selectedTab {
        case .timeline:
            return historyStore.clips.filter { !$0.isHiddenFromTimeline }
        case .pinned:
            let pinnedID = historyStore.pinnedPinboard.id
            return historyStore.clips.filter { $0.pinboardIDs.contains(pinnedID) }
        case .folder(let id):
            return historyStore.clips.filter { $0.pinboardIDs.contains(id) }
        }
    }
}
