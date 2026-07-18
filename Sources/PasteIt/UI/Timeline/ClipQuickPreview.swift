import AppKit
import SwiftUI

/// Space-bar "Quick Look"-style preview shown in a standalone floating window.
///
/// Cards themselves only ever render plain text (see `ClipCardView`) because parsing
/// HTML/RTF into an `NSAttributedString` is expensive while scrolling. This view
/// renders the full styled version on demand for a single item at a time.
struct ClipQuickPreview: View {
    let item: ClipItem
    let historyStore: HistoryStore
    let onClose: () -> Void

    @State private var richText: NSAttributedString = NSAttributedString()

    private var showsRichText: Bool {
        item.htmlText != nil || item.rtfData != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 420, minHeight: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: item.id) {
            if showsRichText {
                richText = RichTextCodec.attributedString(from: item)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(item.title, systemImage: item.primaryType.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("space to close")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

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

    private var imagePreview: some View {
        Group {
            if let image = historyStore.fullImage(for: item) ?? historyStore.thumbnailImage(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ContentUnavailableView("No Preview", systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private var linkPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let preview = historyStore.linkPreviewImage(for: item) {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack(spacing: 8) {
                    if let icon = historyStore.linkIconImage(for: item) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Text(item.linkTitle ?? item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .textSelection(.enabled)
                }
                Text(item.fileURLString ?? item.plainText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        if showsRichText {
            RichTextEditor(attributedText: $richText, isEditable: false)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
        } else {
            ScrollView {
                Text(item.previewText)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }
}
