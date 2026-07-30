import Combine
import Foundation

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
    @Published var query: String = "" {
        didSet {
            guard query != oldValue, !isBatchUpdatingFilters else { return }
            scheduleSearchDebounce()
        }
    }
    @Published private(set) var visibleClips: [ClipItem] = []
    @Published var selectedClipID: UUID?
    @Published var selectedTab: TimelineTab = .timeline {
        didSet {
            guard selectedTab != oldValue, !isBatchUpdatingFilters else { return }
            rebuildVisibleClips()
        }
    }
    @Published var selectedType: ClipType? {
        didSet {
            guard selectedType != oldValue, !isBatchUpdatingFilters else { return }
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
    /// When set, the timeline presents the clip editor for this item.
    @Published var editingClip: ClipItem?
    /// When set, the timeline shows the space-bar quick preview for this item.
    @Published var previewClip: ClipItem?

    let settings: AppSettings
    let historyStore: HistoryStore
    let searchService: SearchService

    weak var panelController: TimelinePanelController?
    var pasteStackController: PasteStackController?

    private var debouncedQuery: String = ""
    private var searchDebounceTask: Task<Void, Never>?
    private var clipsObservation: AnyCancellable?
    private var isBatchUpdatingFilters = false

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
                    self?.rebuildVisibleClips()
                }
            }
        rebuildVisibleClips()
    }

    var selectedClip: ClipItem? {
        guard let selectedClipID else { return visibleClips.first }
        return visibleClips.first { $0.id == selectedClipID }
    }

    /// Resets filters when the timeline panel opens, coalescing into one visibleClips rebuild.
    func resetFiltersForPanelShow() {
        isBatchUpdatingFilters = true
        searchDebounceTask?.cancel()
        query = ""
        debouncedQuery = ""
        selectedTab = .timeline
        selectedType = nil
        selectedSourceApp = nil
        isBatchUpdatingFilters = false
        rebuildVisibleClips()
        // Always start from the first card — don't preserve prior selection/scroll.
        selectFirst(scroll: true)
    }

    func selectFirstIfNeeded() {
        if selectedClipID == nil || !visibleClips.contains(where: { $0.id == selectedClipID }) {
            selectedClipID = visibleClips.first?.id
        }
    }

    func selectFirst(scroll: Bool = false) {
        selectedClipID = visibleClips.first?.id
        if scroll {
            scrollToStartRequest += 1
        }
    }

    /// Stages an accessed clip to the front of history and keeps selection/scroll in sync.
    func promoteAccessedClip(_ item: ClipItem, scroll: Bool = true) {
        historyStore.promoteToFront(item)
        rebuildVisibleClips()
        selectedClipID = item.id
        if scroll {
            scrollToStartRequest += 1
        }
    }

    @discardableResult
    func beginEditingSelectedClip() -> Bool {
        guard let clip = selectedClip else { return false }
        editingClip = clip
        return true
    }

    /// Space-bar "Quick Look" toggle: opens a full-fidelity preview of the selected
    /// clip, or closes it if one is already showing.
    func togglePreviewForSelectedClip() {
        if previewClip != nil {
            previewClip = nil
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
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            debouncedQuery = next
            rebuildVisibleClips()
        }
    }

    private func rebuildVisibleClips() {
        if case .folder(let id) = selectedTab,
           !historyStore.customFolders.contains(where: { $0.id == id }) {
            isBatchUpdatingFilters = true
            selectedTab = .timeline
            isBatchUpdatingFilters = false
        }

        let sourceClips: [ClipItem]
        switch selectedTab {
        case .timeline:
            sourceClips = historyStore.clips.filter { !$0.isHiddenFromTimeline }
        case .pinned:
            let pinnedID = historyStore.pinnedPinboard.id
            sourceClips = historyStore.clips.filter { $0.pinboardIDs.contains(pinnedID) }
        case .folder(let id):
            sourceClips = historyStore.clips.filter { $0.pinboardIDs.contains(id) }
        }

        visibleClips = searchService.search(
            clips: sourceClips,
            query: debouncedQuery,
            selectedType: selectedType,
            sourceApp: selectedSourceApp,
            pinboardID: nil,
            foldedHaystack: { [historyStore] item in
                historyStore.foldedSearchText(for: item)
            }
        )
        selectFirstIfNeeded()
    }
}
