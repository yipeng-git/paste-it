import SwiftUI

struct TimelineView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var historyStore: HistoryStore

    let pasteController: PasteController
    private let settings: AppSettings

    @FocusState private var isSearchFocused: Bool
    /// When false, the real TextField is not in the hierarchy so the panel can't auto-focus it.
    @State private var isSearchActive = false

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
        HStack(spacing: 2) {
            ForEach(TimelineTab.allCases) { tab in
                Button {
                    appState.selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
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
        }
        .padding(3)
        .pasteItCapsuleGlass()
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
        }
    }

    @ViewBuilder
    private func pinMenu(for item: ClipItem) -> some View {
        if item.pinboardIDs.isEmpty {
            Button("Pin") {
                historyStore.pinToDefaultBoard(item)
            }
        } else {
            Button("Unpin") {
                historyStore.unpin(item)
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
            Button("Delete", role: .destructive) { historyStore.delete(item) }
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
