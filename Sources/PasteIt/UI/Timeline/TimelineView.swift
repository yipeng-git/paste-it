import AppKit
import SwiftUI
import PasteItCore

struct TimelineView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var historyStore: HistoryStore

    let pasteController: PasteController
    private let settings: AppSettings

    @FocusState private var isSearchFocused: Bool
    /// When false, the real TextField is not in the hierarchy so the panel can't auto-focus it.
    @State private var isSearchActive = false
    @State private var isShowingCreateFolderSheet = false
    @State private var newFolderName = ""

    init(appState: AppState, pasteController: PasteController) {
        self.appState = appState
        self.pasteController = pasteController
        _historyStore = ObservedObject(wrappedValue: appState.historyStore)
        self.settings = appState.settings
    }

    var body: some View {
        content
            .background(ClearHostingBackground())
            .pasteItPanelGlass()
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
            }
            .onChange(of: appState.selectedClipID) { _, _ in
                // Quick Look retarget: ←/→ or click another card keeps the bubble, swaps content.
                // Defer so we don't nest @Published mutations during view update.
                guard appState.previewClip != nil else { return }
                DispatchQueue.main.async {
                    self.appState.syncPreviewToSelection()
                }
            }
            .sheet(isPresented: $isShowingCreateFolderSheet) {
                CreateFolderSheet(
                    name: $newFolderName,
                    onCreate: { createFolder() },
                    onCancel: {
                        isShowingCreateFolderSheet = false
                        newFolderName = ""
                    }
                )
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
                // Remount on scrollToStartRequest so offset resets to the natural
                // resting position (with leading inset) — no scroll animation, no
                // scrollTo(.leading) which would flush the first card to the edge.
                // LazyHStack: create cards on demand. Avoid windowed spacers sized to
                // full history — multi-million-pt clear views stall panel open.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(clips) { item in
                            card(item, quickIndex: quickIndexes[item.id], isSelected: selectedIDs.contains(item.id))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .padding(.top, 8)
                }
                .id(appState.scrollToStartRequest)

                if clips.isEmpty {
                    VStack(spacing: 10) {
                        Text(emptyMessage)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if appState.selectedFilter != .all, appState.query.isEmpty {
                            Button("Clear filter") {
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

    /// Prefer transient status; otherwise hint while multi-selecting.
    private var toolbarStatusText: String? {
        if let status = appState.statusMessage {
            return status
        }
        let count = appState.orderedSelectedClips.count
        guard count > 1 else { return nil }
        return "\(count) selected — Return to paste"
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

            if historyStore.canCreateCustomFolder {
                Button {
                    appState.dismissPreview()
                    newFolderName = ""
                    isShowingCreateFolderSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .pasteItControlGlass()
                .help("New Folder")
            }
        }
    }

    private func tabButton(_ tab: TimelineTab, title: String, systemImage: String) -> some View {
        Button {
            if appState.selectedTab == tab {
                appState.dismissPreview()
            } else {
                appState.selectedTab = tab
            }
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if appState.selectedTab == tab {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(appState.selectedTab == tab ? .primary : .secondary)
    }

    private func createFolder() {
        guard let board = historyStore.createCustomFolder(name: newFolderName) else { return }
        isShowingCreateFolderSheet = false
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
            return "No matching clips"
        }
        if appState.selectedFilter != .all {
            let label = appState.selectedFilter.title
            switch appState.selectedTab {
            case .pinned:
                return "No \(label) clips in Pinned"
            case .folder:
                return "No \(label) clips in this folder"
            case .timeline:
                return "No \(label) clips"
            }
        }
        switch appState.selectedTab {
        case .timeline:
            return "Copy something to build your clipboard history"
        case .pinned:
            return "Pin clips to keep them here permanently"
        case .folder:
            return "Add clips to this folder from the context menu"
        }
    }

    @ViewBuilder
    private func pinMenu(for item: ClipItem) -> some View {
        // On the Pinned tab, the destructive action already unpins.
        if case .pinned = appState.selectedTab {
            // skip Pin/Unpin here
        } else if historyStore.isPinned(item) {
            Button("Unpin") {
                appState.togglePinned(item)
            }
        } else {
            Button("Pin") {
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
            Menu("Add to Folder") {
                ForEach(available) { folder in
                    Button(folder.name) {
                        appState.pin(item, to: folder)
                    }
                }
            }
        }
        if !memberships.isEmpty {
            Menu("Remove from Folder") {
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
                stage(item, trigger: "double_click", dismissPanel: true)
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
            pinMenu: { pinMenu(for: item) }
        )
    }

    private var deleteTitle: String {
        switch appState.selectedTab {
        case .timeline: return "Delete"
        case .pinned: return "Unpin"
        case .folder: return "Remove from Folder"
        }
    }

    /// Puts the clip on the system pasteboard (replacing current clipboard contents).
    /// Does not auto-paste into the frontmost app.
    /// Promotes the clip to the front (Paste Cmd-C / Return / Quick Paste behavior).
    private func stage(
        _ item: ClipItem,
        mode: PasteController.PasteMode = .normal,
        trigger: String,
        dismissPanel: Bool
    ) {
        appState.selectOnly(item.id)
        let resolvedMode: PasteController.PasteMode =
            settings.pasteAsPlainTextByDefault && mode == .normal ? .plainText : mode

        if dismissPanel {
            if item.primaryType == .image, resolvedMode == .normal {
                Task { @MainActor in
                    guard await pasteController.copyToPasteboardAsync(item, mode: resolvedMode) else { return }
                    logClipStaged(item, mode: resolvedMode, trigger: trigger)
                    dismissThenPromote(item, status: "Copied \(item.title)")
                }
                return
            }
            guard pasteController.copyToPasteboard(item, mode: resolvedMode) else { return }
            logClipStaged(item, mode: resolvedMode, trigger: trigger)
            dismissThenPromote(item, status: "Copied \(item.title)")
            return
        }

        if item.primaryType == .image, resolvedMode == .normal {
            Task { @MainActor in
                guard await pasteController.copyToPasteboardAsync(item, mode: resolvedMode) else { return }
                promoteAfterStage(item, mode: resolvedMode, trigger: trigger)
            }
            return
        }

        guard pasteController.copyToPasteboard(item, mode: resolvedMode) else { return }
        promoteAfterStage(item, mode: resolvedMode, trigger: trigger)
    }

    /// ⌘C with multi-select: copy first selected item only, then collapse selection.
    private func copyFirstOfSelection(trigger: String) {
        let ordered = appState.orderedSelectedClips
        guard let first = ordered.first else { return }
        if ordered.count > 1 {
            appState.selectedClipID = first.id
            stage(first, trigger: trigger, dismissPanel: false)
            appState.clearMultiSelectKeepingAnchor()
        } else {
            stage(first, trigger: trigger, dismissPanel: false)
        }
    }

    /// Return / Shift+Return: paste selection into the frontmost app (synthesized ⌘V).
    private func pasteSelectionSequentially(
        mode: PasteController.PasteMode = .normal,
        trigger: String
    ) {
        let ordered = appState.orderedSelectedClips
        guard !ordered.isEmpty else { return }

        var didPromptForAccessibility = false
        SystemPasteSynthesizer.ensureAccessibilityIfNeeded(didPrompt: &didPromptForAccessibility)
        guard SystemPasteSynthesizer.isAccessibilityTrusted else {
            // Fall back to staging so the user can still ⌘V manually.
            if ordered.count == 1, let only = ordered.first {
                stage(only, mode: mode, trigger: trigger, dismissPanel: true)
                appState.setStatus("Copied — grant Accessibility to auto-paste, or press ⌘V")
            } else {
                appState.setStatus("Grant Accessibility to paste multiple items")
            }
            return
        }

        let resolvedMode: PasteController.PasteMode =
            settings.pasteAsPlainTextByDefault && mode == .normal ? .plainText : mode
        // Capture items and hide immediately — don't collapse multi-select first
        // or the timeline changes face while the panel is still on screen.
        let items = ordered
        let itemToPromote: ClipItem? = items.count == 1 ? items.first : nil
        if items.count == 1, let only = items.first {
            Analytics.clipStaged(
                mode: resolvedMode == .plainText ? "plain" : "normal",
                trigger: trigger,
                clipType: only.primaryType.rawValue,
                tab: analyticsTabKind(appState.selectedTab),
                ageBucket: Analytics.Buckets.age(since: only.createdAt)
            )
        }
        let pasteStack = appState.pasteStackController

        Task { @MainActor in
            // Don't let Paste Stack's ⌘V tap swallow / re-stage our synthesized pastes.
            pasteStack?.suspendPasteIntercept()
            defer { pasteStack?.resumePasteIntercept() }

            // Wait until the panel has fully dismissed and the previous app is key;
            // otherwise the first synthesized ⌘V is swallowed / lost.
            await dismissTimelinePanel()
            try? await Task.sleep(nanoseconds: 100_000_000)

            var pasted = 0
            for item in items {
                let wrote: Bool
                if item.primaryType == .image, resolvedMode == .normal {
                    wrote = await pasteController.copyToPasteboardAsync(item, mode: resolvedMode)
                } else {
                    wrote = pasteController.copyToPasteboard(item, mode: resolvedMode)
                }
                guard wrote else { continue }
                // Settle write → ⌘V → wait for the target app to consume before
                // overwriting the pasteboard (avoids skip/duplicate under load).
                await SystemPasteSynthesizer.pasteWrittenItem()
                pasted += 1
            }
            if items.count > 1 {
                Analytics.clipStaged(
                    mode: resolvedMode == .plainText ? "plain" : "normal",
                    trigger: trigger,
                    clipType: "multi",
                    tab: analyticsTabKind(appState.selectedTab),
                    ageBucket: "multi"
                )
            }
            if pasted == 0 {
                appState.setStatus("Nothing to paste")
            } else if pasted == 1 {
                appState.setStatus(resolvedMode == .plainText ? "Pasted as plain text" : "Pasted")
            } else {
                appState.setStatus("Pasted \(pasted) items")
            }
            // Reorder after paste so SwiftData save / list rebuild never delay ⌘V.
            if let itemToPromote {
                appState.promoteAccessedClip(itemToPromote, scroll: false)
            }
        }
    }

    /// Close now; persist order after the panel is gone (no visible card shuffle).
    private func dismissThenPromote(_ item: ClipItem, status: String) {
        let clipID = item.id
        let appState = self.appState
        if let panelController = appState.panelController {
            panelController.hide {
                Task { @MainActor in
                    appState.setStatus(status)
                    guard let clip = appState.historyStore.clips.first(where: { $0.id == clipID }) else {
                        return
                    }
                    appState.promoteAccessedClip(clip, scroll: false)
                }
            }
        } else {
            appState.setStatus(status)
            appState.promoteAccessedClip(item, scroll: false)
        }
    }

    private func promoteAfterStage(
        _ item: ClipItem,
        mode: PasteController.PasteMode,
        trigger: String
    ) {
        logClipStaged(item, mode: mode, trigger: trigger)
        if appState.panelController?.isVisible == true {
            appState.notePromoteAfterHide(item)
        } else {
            appState.promoteAccessedClip(item, scroll: true)
        }
        appState.setStatus("Copied \(item.title)")
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
                panelController.hide {
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
                    stage(item, trigger: "hotkey_1_9", dismissPanel: true)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
            }
            Button("") {
                pasteSelectionSequentially(trigger: "return")
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("") {
                pasteSelectionSequentially(mode: .plainText, trigger: "shift_return")
            }
            .keyboardShortcut(.return, modifiers: [.shift])

            // Paste: ⌘C copies selected item to the clipboard and promotes it.
            Button("") {
                copyFirstOfSelection(trigger: "cmd_c")
            }
            .keyboardShortcut("c", modifiers: [.command])

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
                TextField("Search history", text: $draft)
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
                Text("Search (⌘F)")
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
            Button("Copy to Clipboard", action: onCopy)
            Button("Copy as Plain Text", action: onCopyPlain)
            Button("Edit", action: onEdit)
                .keyboardShortcut("e")
                .disabled(!canEdit)
            Divider()
            pinMenu()
            Button(deleteHelp, role: .destructive, action: onDelete)
        }
    }
}

private struct CreateFolderSheet: View {
    @Binding var name: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Folder")
                .font(.headline)
            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if canCreate { onCreate() }
                }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
