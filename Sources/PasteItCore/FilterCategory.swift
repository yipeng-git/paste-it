import Foundation

/// User-facing timeline filter categories (not storage `ClipType` cases).
public enum FilterCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case all
    case text
    case number
    case link
    case image
    case file

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return L10n.tr("filter.all", default: "All types")
        case .text: return L10n.tr("filter.text", default: "Text")
        case .number: return L10n.tr("filter.number", default: "Number")
        case .link: return L10n.tr("filter.link", default: "Link")
        case .image: return L10n.tr("filter.image", default: "Image")
        case .file: return L10n.tr("filter.file", default: "File")
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .number: return "textformat.123"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    /// Menu order in the filter popover (excludes `.all` when building the list
    /// with an explicit All row — callers usually iterate `menuItems`).
    public static var menuItems: [FilterCategory] {
        [.all, .text, .number, .link, .image, .file]
    }

    public func matches(primaryTypeRaw: String, plainText: String) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return Self.isTextLike(primaryTypeRaw) && !LooksLikeNumber.matches(plainText)
        case .number:
            return Self.isTextLike(primaryTypeRaw) && LooksLikeNumber.matches(plainText)
        case .link:
            return primaryTypeRaw == "url"
        case .image:
            return primaryTypeRaw == "image"
        case .file:
            return primaryTypeRaw == "file"
        }
    }

    public static func from(typeToken: String) -> FilterCategory? {
        let value = typeToken.lowercased()
        switch value {
        case "all", "any":
            return .all
        case "text", "richtext", "rich text", "html":
            return .text
        case "number", "num", "numbers":
            return .number
        case "link", "url":
            return .link
        case "image", "img", "photo":
            return .image
        case "file", "files", "folder", "folders":
            return .file
        default:
            return FilterCategory(rawValue: value)
        }
    }

    private static func isTextLike(_ raw: String) -> Bool {
        raw == "text" || raw == "richText" || raw == "html"
    }
}
