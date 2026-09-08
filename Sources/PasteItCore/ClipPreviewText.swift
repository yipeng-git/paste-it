import Foundation

/// Shared rules for what a timeline **card** and Space **preview** should show as text.
///
/// Cards always display this resolved string (never raw HTML). Space preview / ⌘E may
/// render rich attributes, but the *plain* content must match this resolver.
public enum ClipPreviewText: Sendable {
    public static func resolve(
        plainText: String,
        /// Already-extracted plain string from HTML/RTF (trimmed). Pass `nil` when there is no rich payload.
        richPlainText: @autoclosure () -> String?,
        hasRichPayload: Bool,
        ocrText: String?,
        fileURLString: String?,
        typeTitle: String
    ) -> String {
        let trimmedPlain = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPlain.isEmpty {
            return plainText
        }

        if hasRichPayload {
            if let richPlainText = richPlainText(), !richPlainText.isEmpty {
                return richPlainText
            }
            // Whitespace-only HTML/RTF (e.g. Chrome nbsp) — never surface the type name as content.
            return ""
        }

        if let ocrText, !ocrText.isEmpty {
            return ocrText
        }

        if let fileURLString {
            return URL(string: fileURLString)?.lastPathComponent ?? fileURLString
        }

        return typeTitle
    }

    /// Bounds card layout/highlighting without truncating the stored or pasted text.
    public struct Summary: Equatable, Sendable {
        public let text: String
        public let characterCount: Int

        public init(_ fullText: String, limit: Int = 1_024) {
            let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            characterCount = trimmed.utf16.count
            let prefix = fullText.prefix(max(0, limit))
            text = String(prefix) + (prefix.endIndex < fullText.endIndex ? "…" : "")
        }

        public var footer: String { ClipPreviewText.characterFooter(count: characterCount) }
    }

    /// Footer under text-like cards.
    public static func characterFooter(forPreviewText previewText: String) -> String {
        let trimmed = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return characterFooter(count: trimmed.utf16.count)
    }

    private static func characterFooter(count: Int) -> String {
        if count == 0 {
            return L10n.tr("clipType.empty", default: "Empty")
        }
        if count == 1 {
            return L10n.tr("clipPreview.oneCharacter", default: "1 character")
        }
        return L10n.tr("clipPreview.characters", default: "%lld characters", count)
    }
}
