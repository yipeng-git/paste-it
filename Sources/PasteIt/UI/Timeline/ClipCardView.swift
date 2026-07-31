import AppKit
import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let historyStore: HistoryStore
    let isSelected: Bool
    let quickIndex: Int?
    var query: String = ""

    private let cardCornerRadius: CGFloat = 18
    private let headerHeight: CGFloat = 52

    @State private var thumbnailImage: NSImage?
    @State private var linkPreviewImage: NSImage?
    @State private var linkIconImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            header
            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            if let footerText = metadataFooterText {
                metadataFooter(footerText)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        .task(id: item.id) {
            historyStore.enrichLinkMetadataIfNeeded(for: item)
            await loadMediaIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.cardDisplayTitle)
                    .font(.system(size: 15, weight: .bold))
                Text(item.createdAt.pasteItCopiedLabel())
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)

            Spacer(minLength: 8)

            if let quickIndex {
                Text("⌘\(quickIndex)")
                    .font(.system(size: 10, weight: .bold).monospaced())
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.22), in: Capsule())
            }

            if let sourceIcon = historyStore.sourceIcon(for: item) {
                Image(nsImage: sourceIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: headerHeight)
        .background(historyStore.bannerColor(for: item))
    }

    // MARK: - Content

    @ViewBuilder
    private var contentBody: some View {
        switch item.primaryType {
        case .image:
            imageContent
        case .url:
            linkContent
        case .file:
            fileContent
        default:
            textContent
        }
    }

    /// Always plain text in the card — parsing/laying out HTML or RTF here is what caused
    /// the stutter while scrolling. The full rendered version is available via the
    /// space-bar quick preview (`ClipQuickPreview`) instead.
    private var textContent: some View {
        highlightedText(item.previewText, font: .system(size: 14, weight: .regular), lineLimit: 8)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private var imageContent: some View {
        GeometryReader { geo in
            Group {
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Color.secondary.opacity(0.06)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var linkContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let preview = linkPreviewImage {
                    GeometryReader { geo in
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                } else if let icon = linkIconImage {
                    ZStack {
                        Color.secondary.opacity(0.08)
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                } else {
                    ZStack {
                        Color.secondary.opacity(0.08)
                        Image(systemName: "link")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                highlightedText(
                    item.linkTitle ?? item.title,
                    font: .system(size: 13, weight: .semibold),
                    lineLimit: 2
                )
                Text(displayURL)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var fileContent: some View {
        VStack(spacing: 10) {
            Image(systemName: item.isDirectoryFileClip ? "folder.fill" : "doc.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            highlightedText(item.previewText, font: .system(size: 13, weight: .medium), lineLimit: 3)
                .multilineTextAlignment(.center)
            if item.storedFileURLs.count > 1 {
                Text("\(item.storedFileURLs.count) items")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 22)
    }

    private func metadataFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            .padding(.top, 2)
    }

    // MARK: - Helpers

    private var metadataFooterText: String? {
        switch item.primaryType {
        case .text, .richText, .html, .mixed:
            guard !item.plainText.isEmpty else { return nil }
            // utf16.count is O(1); Character.count walks grapheme clusters.
            let count = item.plainText.utf16.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .image:
            guard let size = historyStore.imagePixelSize(for: item) else { return nil }
            return "\(size.width) × \(size.height)"
        default:
            return nil
        }
    }

    private var displayURL: String {
        let raw = item.fileURLString ?? item.plainText
        if let url = URL(string: raw) {
            let host = url.host ?? ""
            let path = url.path == "/" ? "" : url.path
            let combined = host + path
            return combined.isEmpty ? raw : combined
        }
        return raw
    }

    private func highlightedText(_ text: String, font: Font, lineLimit: Int) -> some View {
        Group {
            if queryTerms.isEmpty {
                Text(text)
            } else {
                Text(highlightedAttributedString(text))
            }
        }
        .font(font)
        .lineLimit(lineLimit)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var queryTerms: [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.contains(":") }
    }

    private func highlightedAttributedString(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let terms = queryTerms
        guard !terms.isEmpty else { return attributed }

        let lowercased = text.lowercased()
        for term in terms {
            let needle = term.lowercased()
            var searchStart = lowercased.startIndex
            while let range = lowercased.range(of: needle, range: searchStart..<lowercased.endIndex) {
                if let attrStart = AttributedString.Index(range.lowerBound, within: attributed),
                   let attrEnd = AttributedString.Index(range.upperBound, within: attributed) {
                    attributed[attrStart..<attrEnd].backgroundColor = Color(hex: "FFE566")
                    attributed[attrStart..<attrEnd].foregroundColor = .primary
                }
                searchStart = range.upperBound
            }
        }
        return attributed
    }

    private func loadMediaIfNeeded() async {
        switch item.primaryType {
        case .image:
            if thumbnailImage == nil {
                thumbnailImage = historyStore.cachedThumbnailImage(for: item)
            }
            if thumbnailImage == nil {
                thumbnailImage = await historyStore.loadThumbnailImage(for: item)
            }
        case .url:
            if linkPreviewImage == nil, linkIconImage == nil {
                if let cached = historyStore.cachedLinkPreviewImage(for: item) {
                    if item.linkImageRelativePath != nil {
                        linkPreviewImage = cached
                    } else {
                        linkIconImage = cached
                    }
                }
            }
            if linkPreviewImage == nil, item.linkImageRelativePath != nil {
                linkPreviewImage = await historyStore.loadLinkPreviewImage(for: item)
            } else if linkIconImage == nil, item.linkIconRelativePath != nil {
                linkIconImage = await historyStore.loadLinkPreviewImage(for: item)
            }
        default:
            break
        }
    }
}
