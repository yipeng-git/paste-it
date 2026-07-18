import Foundation
import SwiftUI

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

    /// Card banner color by display category: Link / Image / Text.
    var bannerFallbackColor: Color {
        switch self {
        case .url: return Color(hex: "2F7DE8")
        case .image: return Color(hex: "E24B4A")
        case .text, .richText, .html, .file, .mixed: return Color(hex: "34C759")
        }
    }

    /// Card-facing category. Cards only ever show "Text", "Image", or "Link" —
    /// sub-types like HTML/Rich Text/File/Mixed all collapse into "Text" here,
    /// while `title` still exposes the precise underlying type for the editor
    /// and the space-bar quick preview.
    var displayTitle: String {
        switch self {
        case .url: return "Link"
        case .image: return "Image"
        case .text, .richText, .html, .file, .mixed: return "Text"
        }
    }
}
