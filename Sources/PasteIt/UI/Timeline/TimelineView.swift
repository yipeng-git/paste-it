import AppKit
import SwiftUI
import PasteItCore

struct TimelineView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var historyStore: HistoryStore

    let pasteController: PasteController
    @ObservedObject private var settings: AppSettings

    @FocusState private var isSearchFocused: Bool
    /// When false, the real TextField is not in the hierarchy so the panel can't auto-focus it.
    @State private var isSearchActive = false
    @State private var isShowingCreateFolderPopover = false
    @State private var newFolderName = ""
    @State private var accessibilityTrusted = SystemPasteSynthesizer.isAccessibilityTrusted
    @State private var actionIssue: String?
    @State private var retryAction: (() -> Void)?
    @State private var manualCopyReady = false
    @State private var isWorking = false
    @State private var deleteEverywhereItem: ClipItem?
    @Namespace private var tabHighlightNamespace

    init(appState: AppState, pasteController: PasteController) {
        self.appState = appState
        self.pasteController = pasteController
        _historyStore = ObservedObject(wrappedValue: appState.historyStore)
        _settings = ObservedObject(wrappedValue: appState.settings)
    }

    var body: some View {
        content
            .background(ClearHostingBackground())
            .pasteItPanelGlass()
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshPermission()
            }
            .alert(L10n.tr("removal.everywhere", default: "Delete Everywhere"), isPresented: Binding(
                get: { deleteEverywhereItem != nil },
                set: { if !$0 { deleteEverywhereItem = nil } }
            ), presenting: deleteEverywhereItem) { item in
                Button(L10n.tr("common.cancel", default: "Cancel"), role: .cancel) { deleteEverywhereItem = nil }
                Button(L10n.tr("removal.everywhere", default: "Delete Everywhere"), role: .destructive) {
                    historyStore.deleteEverywhere(item)
                    deleteEverywhereItem = nil
                }
            } message: { _ in
                Text(L10n.tr("removal.everywhereDetail", default: "Delete this clip from history, Pinned, and all folders? This cannot be undone."))
            }
            .alert("Paste It", isPresented: Binding(
                get: { actionIssue != nil },
                set: { if !$0 { actionIssue = nil } }
            )) {
                if let retry = retryAction {
                    Button(L10n.tr("action.retry", default: "Retry")) { retry() }
                        .disabled(isWorking)
                }
                if manualCopyReady {
                    Button(L10n.tr("action.returnToApp", default: "Return to App")) {
                        clearIssue()
                        appState.panelController?.hide()
                    }
                }
                if !accessibilityTrusted {
                    Button(L10n.tr("action.enablePaste", default: "Enable Direct Paste")) {
                        clearIssue()
                        SystemPasteSynthesizer.openAccessibilitySettings()
                    }
                }
                Button(L10n.tr("action.dismiss", default: "Dismiss message"), role: .cancel) { clearIssue() }
            } message: {
                Text(actionIssue ?? "")
            }
            .onChange(of: historyStore.removalError) { _, error in
                guard let error else { return }
                clearIssue()
                actionIssue = error
                historyStore.removalError = nil
            }
            .onChange(of: historyStore.clips.count) { _, _ in appState.selectFirstIfNeeded() }
            .onChange(of: appState.selectedTab) { _, _ in
                // Tab switch leaves the peeked clip's context — dismiss only.
                // Card rebuild + selection run asynchronously in AppState.beginTabSwitch().
                appState.dismissPreview()
            }
            .onChange(of: appState.searchFocusRequest) { _, _ in
                appState.dismissPreview()
                isSearchActive = true
                isSearchFocused = true
            }
            .onChange(of: appState.searchBlurRequest) { _, _ in
                resignSearch()
                refreshPermission()
            }
            .onChange(of: appState.selectedClipID) { _, _ in
                // Quick Look retarget: ←/→ or click another card keeps the bubble, swaps content.
                // Defer so we don't nest @Published mutations during view update.
                guard appState.previewClip != nil else { return }
                DispatchQueue.main.async {
                    self.appState.syncPreviewToSelection()
                }
            }
    }

    private var content: some View {
        let clips = appState.visibleClips
        let quickIndexes = Dictionary(
            uniqueKeysWithValues: clips.prefix(9).enumerated().map { ($1.id, $0 + 1) }
        )
        // Avoid per-card `orderedSelectedClips` (scans full visible list).
        var selectedIDs = Set(appState.selectedClipIDs)
        if let id = appState.selectedClipID {
            selectedIDs.insert(id)
        }
        return VStack(spacing: 0) {
            toolbar
            ZStack {
                TimelineCardStrip(
                    clips: clips, version: appState.visibleClipsVersion,
                    selectedIDs: selectedIDs, query: appState.searchHighlight,
                    scrollRequest: appState.scrollToStartRequest,
                    historyRevision: historyStore.revision, tab: appState.selectedTab
                ) { item in
                    card(item, quickIndex: quickIndexes[item.id], isSelected: selectedIDs.contains(item.id))
                }
                .equatable()
                .disabled(isWorking)

                if clips.isEmpty {
                    VStack(spacing: 10) {
                        Text(emptyMessage)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if appState.selectedFilter != .all, appState.query.isEmpty {
                            Button(L10n.tr("timeline.clearFilter", default: "Clear filter")) {
                                appState.setFilter(.all)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.bottom, 12)
                }

                hiddenShortcuts(for: Array(clips.prefix(9)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TimelineFilterButton(appState: appState)
            tabPicker
            if let status = toolbarStatusText {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.dismissPreview()
                }
            HStack(spacing: 8) {
                searchField
                menuButton
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .animation(.easeOut(duration: 0.15), value: appState.statusMessage)
        .animation(.easeOut(duration: 0.15), value: appState.selectedClipIDs.count)
    }

    private var toolbarStatusText: String? {
        if let status = appState.statusMessage { return status }
        guard appState.selectedCount > 1 else { return nil }
        return L10n.tr("action.selectionCount", default: "%lld selected", appState.selectedCount)
    }

    private func refreshPermission() {
        accessibilityTrusted = SystemPasteSynthesizer.isAccessibilityTrusted
    }

    private func clearIssue() {
        actionIssue = nil
        retryAction = nil
        manualCopyReady = false
    }

    private var tabPicker: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(TimelineTab.fixedTabs) { tab in
                    tabButton(tab, title: tab.title, systemImage: tab.systemImage)
                }
                ForEach(historyStore.customFolders) { folder in
                    tabButton(
                        .folder(folder.id),
                        title: folder.name,
                        systemImage: "folder"
                    )
                }
            }
            .padding(3)
            .pasteItCapsuleGlass()
            .animation(.easeOut(duration: 0.22), value: appState.selectedTab.id)

            if historyStore.canCreateCustomFolder {
                Button {
                    appState.dismissPreview()
                    newFolderName = ""
                    isShowingCreateFolderPopover = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .pasteItControlGlass()
                .help(L10n.tr("timeline.newFolderHelp", default: "New Folder"))
                .popover(isPresented: $isShowingCreateFolderPopover, arrowEdge: .bottom) {
                    CreateFolderPopover(
                        name: $newFolderName,
                        onCreate: { createFolder() },
                        onCancel: {
                            isShowingCreateFolderPopover = false
                            newFolderName = ""
                        }
                    )
                }
            }
        }
    }

    private func tabButton(_ tab: TimelineTab, title: String, systemImage: String) -> some View {
        let isSelected = appState.selectedTab == tab
        return Button {
            if isSelected {
                appState.dismissPreview()
            } else {
                withAnimation(.easeOut(duration: 0.22)) {
                    appState.selectedTab = tab
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    pasteItSegmentHighlight(
                        isSelected: isSelected,
                        in: tabHighlightNamespace
                    )
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.68))
    }

    private func createFolder() {
        guard let board = historyStore.createCustomFolder(name: newFolderName) else { return }
        isShowingCreateFolderPopover = false
        newFolderName = ""
        appState.selectedTab = .folder(board.id)
    }

    private var searchField: some View {
        TimelineSearchField(
            appState: appState,
            isSearchFocused: $isSearchFocused,
            isSearchActive: $isSearchActive,
            onActivate: { activateSearch() }
        )
    }

    private var menuButton: some View {
        AppMenuButton(onWillOpen: { appState.dismissPreview() })
            .frame(height: 30)
    }

    private func activateSearch() {
        appState.dismissPreview()
        isSearchActive = true
        // Defer focus so the TextField exists before FocusState applies.
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func resignSearch() {
        isSearchFocused = false
        // Only tear down the TextField when the query is empty, so typed text stays visible.
        if appState.query.isEmpty {
            isSearchActive = false
        }
        appState.panelController?.resignFirstResponder()
    }

    private var emptyMessage: String {
        if !appState.query.isEmpty {
            return L10n.tr("timeline.noMatch", default: "No matching clips")
        }
        if appState.selectedFilter != .all {
            let label = appState.selectedFilter.title
            switch appState.selectedTab {
            case .pinned:
                return L10n.tr("timeline.noTypeInPinned", default: "No %@ clips in Pinned", label)
            case .folder:
                return L10n.tr("timeline.noTypeInFolder", default: "No %@ clips in this folder", label)
            case .timeline:
                return L10n.tr("timeline.noType", default: "No %@ clips", label)
            }
        }
        switch appState.selectedTab {
        case .timeline:
            return L10n.tr("timeline.emptyDefault", default: "Copy something to build your clipboard history")
        case .pinned:
            return L10n.tr("timeline.emptyPinned", default: "Pin clips to keep them here permanently")
        case .folder:
            return L10n.tr("timeline.emptyFolder", default: "Add clips to this folder from the context menu")
        }
    }

    @ViewBuilder
    private func pinMenu(for item: ClipItem) -> some View {
        // On the Pinned tab, the destructive action already unpins.
        if case .pinned = appState.selectedTab {
            // skip Pin/Unpin here
        } else if historyStore.isPinned(item) {
            Button(L10n.tr("timeline.unpin", default: "Unpin")) {
                appState.togglePinned(item)
            }
        } else {
            Button(L10n.tr("timeline.pin", default: "Pin")) {
                appState.togglePinned(item)
            }
        }

        let folders = historyStore.customFolders
        let currentFolderID: UUID? = {
            if case .folder(let id) = appState.selectedTab { return id }
            return nil
        }()
        let available = folders.filter { !item.pinboardIDs.contains($0.id) }
        // Prefer the tab's "Remove from Folder" for the current board.
        let memberships = folders.filter {
            item.pinboardIDs.contains($0.id) && $0.id != currentFolderID
        }

        if !available.isEmpty {
            Menu(L10n.tr("timeline.addToFolder", default: "Add to Folder")) {
                ForEach(available) { folder in
                    Button(folder.name) {
                        appState.pin(item, to: folder)
                    }
                }
            }
        }
        if !memberships.isEmpty {
            Menu(L10n.tr("timeline.removeFromFolder", default: "Remove from Folder")) {
                ForEach(memberships) { folder in
                    Button(folder.name) {
                        appState.unpin(item, from: folder)
                    }
                }
            }
        }
    }

    private func card(_ item: ClipItem, quickIndex: Int?, isSelected: Bool) -> some View {
        TimelineCardCell(
            item: item,
            historyStore: historyStore,
            isSelected: isSelected,
            quickIndex: quickIndex,
            query: appState.searchHighlight,
            isPinned: historyStore.isPinned(item),
            deleteHelp: deleteTitle,
            onSingleClick: {
                resignSearch()
                appState.handlePreviewAwareCardClick(item.id)
            },
            onDoubleClick: {
                resignSearch()
                appState.dismissPreview()
                appState.selectOnly(item.id)
                activate(item, trigger: "double_click")
            },
            onCommandClick: {
                resignSearch()
                appState.toggleMultiSelect(item.id)
            },
            onCopy: {
                resignSearch()
                appState.dismissPreview()
                stage(item, trigger: "card_hover", dismissPanel: false)
            },
            onCopyPlain: {
                resignSearch()
                appState.dismissPreview()
                stage(item, mode: .plainText, trigger: "context_menu", dismissPanel: false)
            },
            canEdit: item.supportsBubbleEditing,
            onEdit: {
                resignSearch()
                _ = appState.beginEditingClip(item)
            },
            onPin: {
                resignSearch()
                appState.dismissPreview()
                appState.togglePinned(item)
            },
            onDelete: {
                resignSearch()
                appState.dismissPreview()
                withAnimation(.easeOut(duration: 0.15)) {
                    appState.removeClipFromCurrentTab(item)
                }
            },
            pinMenu: {
                pinMenu(for: item)
                Divider()
                Button(L10n.tr("removal.everywhere", default: "Delete Everywhere") + "…", role: .destructive) {
                    appState.dismissPreview()
                    deleteEverywhereItem = item
                }
            }
        )
    }

    private var deleteTitle: String {
        appState.removalTitle(for: appState.selectedTab)
    }

    private func activate(_ item: ClipItem? = nil, trigger: String) {
        guard !isWorking else { return }
        if let item { appState.selectOnly(item.id) }
        if settings.timelinePrimaryAction.shouldPaste {
            pasteSelectionSequentially(trigger: trigger)
        } else {
            guard appState.selectedCount == 1, let clip = item ?? appState.selectedClip else {
                clearIssue()
                actionIssue = L10n.tr("action.copySingle", default: "Select one clip to copy. Use ⇧Return to paste multiple clips as plain text.")
                return
            }
            stage(clip, trigger: trigger, dismissPanel: true)
        }
    }

    private func resolvedMode(_ mode: PasteController.PasteMode) -> PasteController.PasteMode {
        settings.pasteAsPlainTextByDefault && mode == .normal ? .plainText : mode
    }

    private func reportFailure(retry: @escaping () -> Void) {
        manualCopyReady = false
        actionIssue = L10n.tr("action.writeFailed", default: "Could not copy this clip. Its content or attachment may be unavailable. Restore the file, then retry.")
        retryAction = retry
    }

    private func stage(
        _ item: ClipItem,
        mode: PasteController.PasteMode = .normal,
        trigger: String,
        dismissPanel: Bool,
        manualFallback: Bool = false
    ) {
        guard !isWorking else { return }
        clearIssue()
        isWorking = true
        let mode = resolvedMode(mode)
        let itemID = item.id
        Task { @MainActor in
            defer { isWorking = false }
            guard await pasteController.copyToPasteboardAsync(item, mode: mode) else {
                reportFailure {
                    guard let current = historyStore.clips.first(where: { $0.id == itemID }) else {
                        clearIssue()
                        return
                    }
                    stage(current, mode: mode, trigger: trigger, dismissPanel: dismissPanel, manualFallback: manualFallback)
                }
                return
            }
            logClipStaged(item, mode: mode, trigger: trigger)
            appState.notePromoteAfterHide(item)
            if manualFallback {
                manualCopyReady = true
                actionIssue = L10n.tr("action.copiedManual", default: "Copied. Return to your app and press ⌘V. Enable Accessibility for direct paste.")
            } else {
                appState.setStatus(L10n.tr("action.copied", default: "Copied to Clipboard"))
                if dismissPanel { appState.panelController?.hide() }
            }
        }
    }

    private func copySelection(trigger: String) {
        guard appState.selectedCount == 1, let first = appState.selectedClip else {
            clearIssue()
            actionIssue = L10n.tr("action.copySingle", default: "Select one clip to copy. Use ⇧Return to paste multiple clips as plain text.")
            return
        }
        stage(first, trigger: trigger, dismissPanel: false)
    }

    private func pasteSelectionSequentially(
        mode: PasteController.PasteMode = .normal,
        trigger: String
    ) {
        let ordered = appState.orderedSelectedClips
        guard !isWorking, !ordered.isEmpty else { return }
        refreshPermission()
        guard accessibilityTrusted else {
            if ordered.count == 1, let only = ordered.first {
                stage(only, mode: mode, trigger: trigger, dismissPanel: false, manualFallback: true)
            } else {
                clearIssue()
                actionIssue = L10n.tr("action.multiPermission", default: "Enable Accessibility to paste multiple clips, or select one clip to copy manually.")
            }
            return
        }
        clearIssue()
        isWorking = true
        let mode = resolvedMode(mode)
        let target = NSWorkspace.shared.frontmostApplication
        Task { @MainActor in
            defer { isWorking = false }
            // Prepare/write the first clip while recovery feedback is still visible.
            guard let first = ordered.first,
                  await pasteController.copyToPasteboardAsync(first, mode: mode) else {
                reportFailure { pasteSelectionSequentially(mode: mode, trigger: trigger) }
                return
            }
            let stack = appState.pasteStackController
            stack?.suspendPasteIntercept()
            defer { stack?.resumePasteIntercept() }
            await dismissTimelinePanel()
            try? await Task.sleep(nanoseconds: 100_000_000)
            for (index, item) in ordered.enumerated() {
                guard SystemPasteSynthesizer.isAccessibilityTrusted,
                      let target, !target.isTerminated,
                      target.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                    actionIssue = L10n.tr("action.focusChanged", default: "Paste stopped because the destination or permission changed. Focus your destination and try the remaining clips again.")
                    recoverSelection(Array(ordered.dropFirst(index)))
                    return
                }
                if index > 0, !(await pasteController.copyToPasteboardAsync(item, mode: mode)) {
                    reportFailure { pasteSelectionSequentially(mode: mode, trigger: trigger) }
                    recoverSelection(Array(ordered.dropFirst(index)))
                    return
                }
                await SystemPasteSynthesizer.pasteWrittenItem()
            }
            appState.setStatus(L10n.tr("action.pasteSent", default: "Paste request sent"))
            if ordered.count == 1, let only = ordered.first {
                logClipStaged(only, mode: mode, trigger: trigger)
                appState.promoteAccessedClip(only, scroll: false)
            } else {
                Analytics.clipStaged(mode: mode == .plainText ? "plain" : "normal", trigger: trigger,
                    clipType: "multi", tab: analyticsTabKind(appState.selectedTab), ageBucket: "multi")
            }
        }
    }

    private func recoverSelection(_ items: [ClipItem]) {
        appState.panelController?.showPreservingContext()
        appState.selectClipsForRecovery(items.map(\.id))
    }

    private func logClipStaged(
        _ item: ClipItem,
        mode: PasteController.PasteMode,
        trigger: String
    ) {
        Analytics.clipStaged(
            mode: mode == .plainText ? "plain" : "normal",
            trigger: trigger,
            clipType: item.primaryType.rawValue,
            tab: analyticsTabKind(appState.selectedTab),
            ageBucket: Analytics.Buckets.age(since: item.createdAt)
        )
    }

    /// Starts the panel slide-out immediately and returns after it has orderOut.
    private func dismissTimelinePanel() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if let panelController = appState.panelController {
                panelController.hide(preserveContext: true) {
                    continuation.resume()
                }
            } else {
                continuation.resume()
            }
        }
    }

    private func analyticsTabKind(_ tab: TimelineTab) -> String {
        switch tab {
        case .timeline: return "default"
        case .pinned: return "pinned"
        case .folder: return "folder"
        }
    }

    private func hiddenShortcuts(for clips: [ClipItem]) -> some View {
        Group {
            ForEach(Array(clips.enumerated()), id: \.element.id) { index, item in
                Button("") {
                    activate(item, trigger: "hotkey_1_9")
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
            }
            Button("") {
                activate(trigger: "return")
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("") {
                pasteSelectionSequentially(mode: .plainText, trigger: "shift_return")
            }
            .keyboardShortcut(.return, modifiers: [.shift])

            // Paste: ⌘C copies selected item to the clipboard and promotes it.
            Button("") {
                copySelection(trigger: "cmd_c")
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("") {
                appState.undoLastRemoval()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(!historyStore.canUndoRemoval)

            Button("") {
                _ = appState.beginEditingSelectedClip()
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button("") {
                appState.togglePreviewForSelectedClip()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("") {
                if appState.previewClip != nil {
                    appState.dismissPreview()
                } else if isSearchActive || isSearchFocused {
                    resignSearch()
                } else {
                    appState.panelController?.hide()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("") {
                activateSearch()
            }
            .keyboardShortcut("f", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

/// Owns the live search draft so typing does not `@Published`-refresh the card strip.
private struct TimelineSearchField: View {
    @ObservedObject var appState: AppState
    var isSearchFocused: FocusState<Bool>.Binding
    @Binding var isSearchActive: Bool
    var onActivate: () -> Void
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if isSearchActive {
                TextField(L10n.tr("timeline.searchHistory", default: "Search history"), text: $draft)
                    .textFieldStyle(.plain)
                    .focused(isSearchFocused)
                    .onSubmit {
                        // Keep focus after submit; Esc still resigns.
                    }
                if !draft.isEmpty {
                    Button {
                        draft = ""
                        appState.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(L10n.tr("timeline.search", default: "Search (⌘F)"))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onActivate()
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 260, height: 30)
        .pasteItControlGlass()
        .onTapGesture {
            if !isSearchActive {
                onActivate()
            }
        }
        .onAppear { draft = appState.query }
        .onChange(of: draft) { _, newValue in
            appState.applySearchTyping(newValue)
        }
        .onChange(of: appState.searchFieldSeed) { _, _ in
            draft = appState.query
        }
    }
}

/// A dependency boundary: status/focus/toolbar changes do not reevaluate the lazy strip.
private struct TimelineCardStrip<Card: View>: View, Equatable {
    let clips: [ClipItem]
    let version: UInt64
    let selectedIDs: Set<UUID>
    let query: String
    let scrollRequest: Int
    let historyRevision: UInt64
    let tab: TimelineTab
    @ViewBuilder let card: (ClipItem) -> Card

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.version == rhs.version && lhs.selectedIDs == rhs.selectedIDs
            && lhs.query == rhs.query && lhs.scrollRequest == rhs.scrollRequest
            && lhs.historyRevision == rhs.historyRevision && lhs.tab == rhs.tab
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(clips) { item in card(item) }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 8)
            .background(TimelineScrollReset(request: scrollRequest))
        }
    }
}

/// Per-card wrapper so hover state stays local and the action bar sits above
/// `CardClickOverlay` (so button clicks are not also treated as card selects).
private struct TimelineCardCell<PinMenu: View>: View {
    let item: ClipItem
    let historyStore: HistoryStore
    let isSelected: Bool
    let quickIndex: Int?
    let query: String
    let isPinned: Bool
    let deleteHelp: String
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void
    let onCommandClick: () -> Void
    let onCopy: () -> Void
    let onCopyPlain: () -> Void
    let canEdit: Bool
    let onEdit: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let pinMenu: () -> PinMenu

    @State private var isHovered = false

    var body: some View {
        ClipCardView(
            item: item,
            historyStore: historyStore,
            isSelected: isSelected,
            quickIndex: quickIndex,
            query: query
        )
        .frame(width: 238, height: 232)
        .background {
            ClipCardFrameRegistrar(id: item.id)
        }
        // AppKit CardClickOverlay owns click handling so single-select is
        // immediate (SwiftUI single+double onTapGesture waits ~400ms).
        .overlay {
            CardClickOverlay(
                onSingleClick: onSingleClick,
                onDoubleClick: onDoubleClick,
                onCommandClick: onCommandClick
            )
        }
        .overlay(alignment: .bottom) {
            if isHovered {
                CardHoverActionBar(
                    isPinned: isPinned,
                    canEdit: canEdit,
                    deleteHelp: deleteHelp,
                    onCopy: onCopy,
                    onEdit: onEdit,
                    onPin: onPin,
                    onDelete: onDelete
                )
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .draggable(item.id.uuidString)
        .contextMenu {
            Button(L10n.tr("timeline.copy", default: "Copy to Clipboard"), action: onCopy)
            Button(L10n.tr("timeline.copyPlain", default: "Copy as Plain Text"), action: onCopyPlain)
            Button(L10n.tr("timeline.edit", default: "Edit"), action: onEdit)
                .keyboardShortcut("e")
                .disabled(!canEdit)
            Divider()
            pinMenu()
            Button(deleteHelp, role: .destructive, action: onDelete)
        }
    }
}

private struct CreateFolderPopover: View {
    @Binding var name: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("timeline.newFolder", default: "New Folder"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(L10n.tr("folders.namePlaceholder", default: "Folder name"), text: $name)
                .textFieldStyle(.plain)
                .focused($isNameFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .pasteItControlGlass()
                .onSubmit {
                    if canCreate { onCreate() }
                }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L10n.tr("common.cancel", default: "Cancel"), action: onCancel)
                    .pasteItGlassButtonStyle()
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("common.create", default: "Create"), action: onCreate)
                    .pasteItGlassButtonStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(14)
        .frame(width: 280)
        .pasteItPopoverChrome()
        .onAppear {
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
    }
}
