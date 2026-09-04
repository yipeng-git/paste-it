import AppKit
import SwiftUI

/// Space-bar preview bubble: bottom sits on the timeline panel, height grows with content.
/// Content-only glass bubble (no caret, no "space to close" chrome).
struct ClipQuickPreview: View {
    let item: ClipItem
    @ObservedObject var historyStore: HistoryStore
    /// Bumped by AppState to enter text editing (hover Edit / ⌘E).
    var editRequest: Int = 0
    let onClose: () -> Void
    /// Text / OCR editing focus so the host bubble can take/resign key.
    var onEditingChanged: (Bool) -> Void = { _ in }

    private enum ImageTab: String, CaseIterable, Identifiable {
        case image = "Image"
        case text = "Text"
        var id: String { rawValue }
    }

    @State private var loadedItemID: UUID?
    @State private var plainText: String = ""
    @State private var richText: NSAttributedString = NSAttributedString()
    @State private var baselinePlain: String = ""
    @State private var baselineRich: NSAttributedString = NSAttributedString()
    @State private var textFocusToken: Int = 0
    @State private var isEditingText = false

    @State private var imageTab: ImageTab = .image
    @State private var isEditingOCR = false
    @State private var ocrDraft = ""
    @State private var isRerunningOCR = false

    @FocusState private var isTextFocused: Bool
    @FocusState private var isOCREditorFocused: Bool

    init(
        item: ClipItem,
        historyStore: HistoryStore,
        editRequest: Int = 0,
        onClose: @escaping () -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.item = item
        self.historyStore = historyStore
        self.editRequest = editRequest
        self.onClose = onClose
        self.onEditingChanged = onEditingChanged

        // Seed editor state synchronously so the first paint isn't empty.
        let usesRich = item.primaryType == .html
            || item.primaryType == .richText
            || item.htmlText != nil
            || item.rtfData != nil
        if usesRich {
            let readable = RichTextCodec.glassReadable(RichTextCodec.attributedString(from: item))
            _richText = State(initialValue: readable)
            _baselineRich = State(initialValue: (readable.copy() as? NSAttributedString) ?? NSAttributedString(attributedString: readable))
            _plainText = State(initialValue: "")
            _baselinePlain = State(initialValue: "")
        } else {
            let text = item.previewText
            _plainText = State(initialValue: text)
            _baselinePlain = State(initialValue: text)
            _richText = State(initialValue: NSAttributedString())
            _baselineRich = State(initialValue: NSAttributedString())
        }
        _loadedItemID = State(initialValue: item.id)
        _ocrDraft = State(initialValue: item.ocrText ?? "")
    }

    private var showsRichText: Bool {
        item.primaryType == .html
            || item.primaryType == .richText
            || item.htmlText != nil
            || item.rtfData != nil
    }

    private var hasOCRText: Bool {
        !(item.ocrText?.isEmpty ?? true)
    }

    private var canRerunOCR: Bool {
        item.primaryType == .image && !(item.blobRelativePath?.isEmpty ?? true)
    }

    private var isTextLikePreview: Bool {
        switch item.primaryType {
        case .url, .image: return false
        default: return true
        }
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ClearHostingBackground())
            .pasteItBubbleGlass()
            .task(id: item.id) {
                if let previous = loadedItemID, previous != item.id {
                    commitTextEdits(for: previous)
                }
                loadContent(for: item)
                loadedItemID = item.id
                imageTab = .image
                isEditingOCR = false
                isEditingText = false
                isTextFocused = false
                ocrDraft = item.ocrText ?? ""
                isRerunningOCR = false
                // Keep timeline key so Space can dismiss without typing into the bubble.
                onEditingChanged(false)
            }
            .onChange(of: editRequest) { _, _ in
                beginTextEditing()
            }
            .onChange(of: item.ocrText) { _, newValue in
                guard !isEditingOCR else { return }
                ocrDraft = newValue ?? ""
            }
            .onChange(of: isTextFocused) { _, focused in
                publishEditingFocus()
                if !focused, isEditingText, !showsRichText {
                    commitTextEdits(for: item.id)
                    isEditingText = false
                    onEditingChanged(false)
                } else if !focused {
                    commitTextEdits(for: item.id)
                }
            }
            .onChange(of: isEditingOCR) { _, editing in
                publishEditingFocus()
                if editing { isOCREditorFocused = true }
            }
            .onChange(of: isOCREditorFocused) { _, _ in
                publishEditingFocus()
            }
            .onKeyPress(.escape) {
                if isEditingOCR {
                    cancelOCREditing()
                    return .handled
                }
                if isEditingText {
                    endTextEditing()
                    return .handled
                }
                commitTextEdits(for: item.id)
                onClose()
                return .handled
            }
            .onDisappear {
                if let id = loadedItemID {
                    commitTextEdits(for: id)
                }
                isEditingOCR = false
                isEditingText = false
                onEditingChanged(false)
            }
            .localizedRefreshTrigger()
    }

    private func publishEditingFocus() {
        onEditingChanged(isEditingText || isEditingOCR || isOCREditorFocused)
    }

    @MainActor
    private func beginTextEditing() {
        guard isTextLikePreview, !isEditingText else { return }
        isEditingText = true
        onEditingChanged(true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            textFocusToken += 1
            if !showsRichText {
                isTextFocused = true
            }
        }
    }

    private func endTextEditing() {
        commitTextEdits(for: item.id)
        isTextFocused = false
        isEditingText = false
        onEditingChanged(false)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch item.primaryType {
        case .image:
            imagePreview
        case .url:
            linkPreview
        default:
            textPreview
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        Group {
            if isEditingText {
                if showsRichText {
                    RichTextEditor(
                        attributedText: $richText,
                        isEditable: true,
                        focusToken: textFocusToken,
                        onEditingChanged: { editing in
                            if editing {
                                onEditingChanged(true)
                            } else {
                                commitTextEdits(for: item.id)
                                isEditingText = false
                                onEditingChanged(false)
                            }
                        }
                    )
                } else {
                    TextEditor(text: $plainText)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .focused($isTextFocused)
                }
            } else if showsRichText {
                ScrollView {
                    Text(AttributedString(richText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .contentShape(Rectangle())
                .onTapGesture { beginTextEditing() }
            } else {
                ScrollView {
                    Text(plainText)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .contentShape(Rectangle())
                .onTapGesture { beginTextEditing() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var linkPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.linkTitle ?? item.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .textSelection(.enabled)
            Text(item.fileURLString ?? item.plainText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            let rawURL = item.fileURLString ?? item.plainText
            if LinkWebPreview.resolvedURL(from: rawURL) != nil {
                LinkWebPreview(urlString: rawURL)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No URL", systemImage: "link")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Image — tabbed Image / OCR

    private var imagePreview: some View {
        VStack(spacing: 10) {
            imageTabPicker

            Group {
                switch imageTab {
                case .image:
                    imageViewport
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                case .text:
                    ocrPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var imageTabPicker: some View {
        HStack(spacing: 2) {
            ForEach(ImageTab.allCases) { tab in
                Button {
                    imageTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            pasteItSegmentHighlight(isSelected: imageTab == tab)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(imageTab == tab ? .primary : .secondary)
            }
        }
        .padding(3)
        .pasteItCapsuleGlass()
    }

    private var imageViewport: some View {
        ZStack {
            Color.clear
                .pasteItPreviewInsetGlass()

            if let image = historyStore.fullImage(for: item) ?? historyStore.thumbnailImage(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ContentUnavailableView("No Preview", systemImage: "photo")
            }
        }
    }

    private var ocrPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if isEditingOCR {
                    Button("Cancel") { cancelOCREditing() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("Save") { saveOCREditing() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Button("Copy") { copyOCRText() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .disabled(!hasOCRText)
                    Button("Edit") { beginOCREditing() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button {
                        rerunOCR()
                    } label: {
                        if isRerunningOCR {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("Re-run")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .disabled(isRerunningOCR || !canRerunOCR)
                }
            }

            if isEditingOCR {
                TextEditor(text: $ocrDraft)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($isOCREditorFocused)
                    .padding(6)
                    .pasteItControlGlass()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isRerunningOCR && !hasOCRText {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Recognizing…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let ocrText = item.ocrText, !ocrText.isEmpty {
                ScrollView {
                    Text(ocrText)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("No text detected", systemImage: "text.viewfinder")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Load / save text

    private func loadContent(for item: ClipItem) {
        let usesRich = item.primaryType == .html
            || item.primaryType == .richText
            || item.htmlText != nil
            || item.rtfData != nil
        if usesRich {
            let attributed = RichTextCodec.glassReadable(RichTextCodec.attributedString(from: item))
            richText = attributed
            baselineRich = (attributed.copy() as? NSAttributedString) ?? NSAttributedString(attributedString: attributed)
            plainText = ""
            baselinePlain = ""
        } else {
            let text = item.previewText
            plainText = text
            baselinePlain = text
            richText = NSAttributedString()
            baselineRich = NSAttributedString()
        }
    }

    private func commitTextEdits(for id: UUID) {
        guard let clip = historyStore.clips.first(where: { $0.id == id })
                ?? (item.id == id ? item : nil) else { return }

        switch clip.primaryType {
        case .url, .image:
            return
        default:
            break
        }

        let usesRich = clip.primaryType == .html
            || clip.primaryType == .richText
            || clip.htmlText != nil
            || clip.rtfData != nil
        if usesRich {
            guard !richText.isEqual(to: baselineRich) else { return }
            let title = resolvedTitle(from: richText.string, fallbackType: clip.primaryType)
            historyStore.update(
                clip,
                title: title,
                plainText: RichTextCodec.plainText(from: richText),
                htmlText: RichTextCodec.html(from: richText),
                rtfData: RichTextCodec.rtf(from: richText)
            )
            baselineRich = (richText.copy() as? NSAttributedString) ?? NSAttributedString(attributedString: richText)
        } else {
            guard plainText != baselinePlain else { return }
            let title = resolvedTitle(from: plainText, fallbackType: clip.primaryType)
            historyStore.update(clip, title: title, plainText: plainText)
            baselinePlain = plainText
        }
    }

    private func resolvedTitle(from source: String, fallbackType: ClipType) -> String {
        let fromText = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(fromText.prefix(80))
        return clipped.isEmpty ? fallbackType.title : clipped
    }

    // MARK: - OCR

    private func beginOCREditing() {
        ocrDraft = item.ocrText ?? ""
        isEditingOCR = true
        onEditingChanged(true)
    }

    private func saveOCREditing() {
        historyStore.updateOCRText(for: item.id, text: ocrDraft, allowEmpty: true)
        isEditingOCR = false
        ocrDraft = item.ocrText ?? ""
    }

    private func cancelOCREditing() {
        ocrDraft = item.ocrText ?? ""
        isEditingOCR = false
    }

    private func copyOCRText() {
        let text = isEditingOCR ? ocrDraft : (item.ocrText ?? "")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func rerunOCR() {
        guard canRerunOCR, !isRerunningOCR else { return }
        isRerunningOCR = true
        imageTab = .text
        Task { @MainActor in
            await historyStore.rerunOCR(for: item)
            isRerunningOCR = false
            ocrDraft = item.ocrText ?? ""
        }
    }
}
