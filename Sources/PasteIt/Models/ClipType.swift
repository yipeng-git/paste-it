import Foundation
import SwiftUI
import PasteItCore

enum ClipType: String, Codable, CaseIterable, Identifiable {
    case text
    case richText
    case html
    case image
    case file
    case url
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .html: return "HTML"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "Link"
        case .mixed: return "Mixed"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "doc.richtext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .mixed: return "square.stack.3d.up"
        }
    }

    /// Card banner color by display category.
    var bannerFallbackColor: Color {
        switch self {
        case .url: return Color(hex: "2F7DE8")
        case .image: return Color(hex: "E24B4A")
        case .file: return Color(hex: "AF52DE")
        case .text, .richText, .html, .mixed: return Color(hex: "34C759")
        }
    }

    /// Card-facing category label.
    ///
    /// File stays File (not collapsed into Text). Number is decided at the call
    /// site via `LooksLikeNumber` when the underlying type is text-like.
    var displayTitle: String {
        switch self {
        case .url: return "Link"
        case .image: return "Image"
        case .file: return "File"
        case .text, .richText, .html, .mixed: return "Text"
        }
    }

    var isTextLike: Bool {
        switch self {
        case .text, .richText, .html: return true
        case .image, .file, .url, .mixed: return false
        }
    }
}

extension ClipItem {
    /// Header label for timeline cards (File / Folder / Number / …).
    var cardDisplayTitle: String {
        switch primaryType {
        case .file:
            return isDirectoryFileClip ? "Folder" : "File"
        case .text, .richText, .html:
            return LooksLikeNumber.matches(plainText) ? "Number" : "Text"
        default:
            return primaryType.displayTitle
        }
    }

    var isDirectoryFileClip: Bool {
        guard primaryType == .file else { return false }
        let urls = storedFileURLs
        guard urls.count == 1, let url = urls.first else { return false }
        return ClipTypeResolver.isDirectoryURL(url)
    }

    var storedFileURLs: [URL] {
        guard let fileURLString, !fileURLString.isEmpty else { return [] }
        return fileURLString
            .split(whereSeparator: \.isNewline)
            .compactMap { URL(string: String($0)) }
    }

    /// Window title for Space quick preview (Preview.app-style document name).
    var previewWindowTitle: String {
        let collapsed = title
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if collapsed.isEmpty {
            return cardDisplayTitle
        }
        if collapsed.count <= 60 {
            return collapsed
        }
        return String(collapsed.prefix(59)) + "…"
    }
}
