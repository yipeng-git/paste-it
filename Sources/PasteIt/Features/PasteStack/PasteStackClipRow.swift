import AppKit
import SwiftUI

/// Compact queue row — not a timeline card. One line of context is enough to pick the next paste.
struct PasteStackClipRow: View {
    let item: ClipItem
    let historyStore: HistoryStore
    let isNext: Bool

    @State private var thumbnailImage: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            leadingVisual
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.cardDisplayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isNext {
                        Text("NEXT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if let sourceIcon = historyStore.sourceIcon(for: item) {
                        Image(nsImage: sourceIcon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                Text(previewLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: PasteStackPanelLayout.rowHeight, maxHeight: PasteStackPanelLayout.rowHeight, alignment: .leading)
        .pasteItStackRowGlass(isHighlighted: isNext)
        .overlay {
            if #unavailable(macOS 26) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isNext ? Color.accentColor.opacity(0.85) : Color.black.opacity(0.06), lineWidth: isNext ? 1.5 : 1)
            } else if isNext {
                PasteItGlass.stackRowShape
                    .stroke(Color.accentColor.opacity(0.85), lineWidth: 1.5)
            }
        }
        .task(id: item.id) {
            await loadThumbnailIfNeeded()
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        Group {
            if let thumbnailImage {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    historyStore.bannerColor(for: item)
                    Image(systemName: item.primaryType.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var previewLine: String {
        let collapsed = item.previewText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty {
            return item.title
        }
        return collapsed
    }

    private func loadThumbnailIfNeeded() async {
        switch item.primaryType {
        case .image:
            thumbnailImage = historyStore.cachedThumbnailImage(for: item)
            if thumbnailImage == nil {
                thumbnailImage = await historyStore.loadThumbnailImage(for: item)
            }
        case .url:
            if let cached = historyStore.cachedLinkPreviewImage(for: item) {
                thumbnailImage = cached
            } else if item.linkImageRelativePath != nil || item.linkIconRelativePath != nil {
                thumbnailImage = await historyStore.loadLinkPreviewImage(for: item)
            }
        default:
            break
        }
    }
}
