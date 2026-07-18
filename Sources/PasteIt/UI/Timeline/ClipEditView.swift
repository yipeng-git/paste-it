import AppKit
import SwiftUI

struct ClipEditView: View {
    let item: ClipItem
    let historyStore: HistoryStore
    let onClose: () -> Void

    @State private var title: String
    @State private var plainText: String
    @State private var attributedText: NSAttributedString
    @FocusState private var isEditorFocused: Bool

    private var usesRichEditor: Bool {
        item.primaryType == .html
            || item.primaryType == .richText
            || item.htmlText != nil
            || item.rtfData != nil
    }

    init(item: ClipItem, historyStore: HistoryStore, onClose: @escaping () -> Void) {
        self.item = item
        self.historyStore = historyStore
        self.onClose = onClose
        _title = State(initialValue: item.title)
        _plainText = State(initialValue: item.previewText)
        _attributedText = State(initialValue: RichTextCodec.attributedString(from: item))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            editor
            Divider()
            footer
        }
        .frame(minWidth: 420, minHeight: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isEditorFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.bold())

            Spacer(minLength: 8)

            Text(item.primaryType.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var editor: some View {
        if usesRichEditor {
            RichTextEditor(attributedText: $attributedText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        } else {
            TextEditor(text: $plainText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .focused($isEditorFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel") { onClose() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save as New") {
                saveAsNew()
                onClose()
            }

            Button("Apply") {
                applyChanges()
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let source = usesRichEditor ? attributedText.string : plainText
        let fromText = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(fromText.prefix(80)).isEmpty ? item.primaryType.title : String(fromText.prefix(80))
    }

    private func applyChanges() {
        if usesRichEditor {
            historyStore.update(
                item,
                title: resolvedTitle,
                plainText: RichTextCodec.plainText(from: attributedText),
                htmlText: RichTextCodec.html(from: attributedText),
                rtfData: RichTextCodec.rtf(from: attributedText)
            )
        } else {
            historyStore.update(item, title: resolvedTitle, plainText: plainText)
        }
    }

    private func saveAsNew() {
        if usesRichEditor {
            historyStore.saveAsNew(
                from: item,
                title: resolvedTitle,
                plainText: RichTextCodec.plainText(from: attributedText),
                htmlText: RichTextCodec.html(from: attributedText),
                rtfData: RichTextCodec.rtf(from: attributedText)
            )
        } else {
            historyStore.saveAsNew(from: item, title: resolvedTitle, plainText: plainText)
        }
    }
}
