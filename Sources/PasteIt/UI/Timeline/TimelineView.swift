import SwiftUI

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
                appState.selectFirstIfNeeded()
            }
            .onChange(of: appState.searchFocusRequest) { _, _ in
                isSearchActive = true
                isSearchFocused = true
            }
            .onChange(of: appState.searchBlurRequest) { _, _ in
                resignSearch()
            }
            .onChange(of: appState.selectedClipID) { _, _ in
                // Mirrors Quick Look: switching selection updates an already-open preview window.
                // Defer the write so we don't nest @Published mutations during view update.
                guard appState.previewClip != nil else { return }
                let next = appState.selectedClip
                DispatchQueue.main.async {
                    if self.appState.previewClip != nil {
                        self.appState.previewClip = next
                    }
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
        return VStack(spacing: 0) {
            toolbar
            ZStack {
                // Remount on scrollToStartRequest so offset resets to the natural
                // resting position (with leading inset) — no scroll animation, no
                // scrollTo(.leading) which would flush the first card to the edge.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(clips.prefix(30).enumerated()), id: \.element.id) { index, item in
                            card(item, quickIndex: index < 9 ? index + 1 : nil)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .padding(.top, 8)
                }
                .id(appState.scrollToStartRequest)

                if clips.isEmpty {
                    Text(emptyMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }

                hiddenShortcuts(for: Array(clips.prefix(9)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            tabPicker
            if let status = appState.statusMessage {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
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
            appState.selectedTab = tab
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if isSearchActive {
                TextField("Search history", text: $appState.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        // Keep focus after submit; Esc still resigns.
                    }
                if !appState.query.isEmpty {
                    Button {
                        appState.query = ""
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
                        activateSearch()
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 260, height: 30)
        .pasteItControlGlass()
        .onTapGesture {
            if !isSearchActive {
                activateSearch()
            }
        }
    }

    private var menuButton: some View {
        AppMenuButton()
            .frame(height: 30)
    }

    private func activateSearch() {
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
                historyStore.unpinFromPinnedBoard(item)
            }
        } else {
            Button("Pin") {
                historyStore.pinToPinnedBoard(item)
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
                        historyStore.pin(item, to: folder)
                    }
                }
            }
        }
        if !memberships.isEmpty {
            Menu("Remove from Folder") {
                ForEach(memberships) { folder in
                    Button(folder.name) {
                        historyStore.unpin(item, from: folder)
                    }
                }
            }
        }
    }

    private func card(_ item: ClipItem, quickIndex: Int?) -> some View {
        ClipCardView(
            item: item,
            historyStore: historyStore,
            isSelected: appState.selectedClipID == item.id,
            quickIndex: quickIndex,
            query: appState.query
        )
        .frame(width: 238, height: 232)
        .onTapGesture {
            // Paste: single click only selects — does not reorder or stage.
            resignSearch()
            appState.selectedClipID = item.id
        }
        .onTapGesture(count: 2) {
            resignSearch()
            stage(item, dismissPanel: true)
        }
        .draggable(item.id.uuidString)
        .contextMenu {
            Button("Copy to Clipboard") { stage(item, dismissPanel: false) }
            Button("Copy as Plain Text") { stage(item, mode: .plainText, dismissPanel: false) }
            Button("Edit") { appState.editingClip = item }
                .keyboardShortcut("e")
            Divider()
            pinMenu(for: item)
            Button(deleteTitle, role: .destructive) {
                historyStore.removeFromTab(item, tab: appState.selectedTab)
            }
        }
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
        dismissPanel: Bool
    ) {
        appState.selectedClipID = item.id
        let resolvedMode: PasteController.PasteMode =
            settings.pasteAsPlainTextByDefault && mode == .normal ? .plainText : mode

        if item.primaryType == .image, resolvedMode == .normal {
            Task { @MainActor in
                guard await pasteController.copyToPasteboardAsync(item, mode: resolvedMode) else { return }
                promoteAfterStage(item, dismissPanel: dismissPanel)
            }
            return
        }

        guard pasteController.copyToPasteboard(item, mode: resolvedMode) else { return }
        promoteAfterStage(item, dismissPanel: dismissPanel)
    }

    private func promoteAfterStage(_ item: ClipItem, dismissPanel: Bool) {
        appState.promoteAccessedClip(item, scroll: !dismissPanel)
        appState.setStatus("Copied \(item.title)")
        if dismissPanel {
            appState.panelController?.hide()
        }
    }

    private func hiddenShortcuts(for clips: [ClipItem]) -> some View {
        Group {
            ForEach(Array(clips.enumerated()), id: \.element.id) { index, item in
                Button("") {
                    stage(item, dismissPanel: true)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
            }
            Button("") {
                if let selected = appState.selectedClip {
                    stage(selected, dismissPanel: true)
                }
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("") {
                if let selected = appState.selectedClip {
                    stage(selected, mode: .plainText, dismissPanel: true)
                }
            }
            .keyboardShortcut(.return, modifiers: [.shift])

            // Paste: ⌘C copies selected item to the clipboard and promotes it.
            Button("") {
                if let selected = appState.selectedClip {
                    stage(selected, dismissPanel: false)
                }
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
                    appState.previewClip = nil
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
