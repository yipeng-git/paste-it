import Foundation

/// Shared rules for what a timeline **card** and Space **preview** should show as text.
///
/// Cards always display this resolved string (never raw HTML). Space preview / ⌘E may
/// render rich attributes, but the *plain* content must match this resolver.
public enum ClipPreviewText: Sendable {
    public static func resolve(
        plainText: String,
        /// Already-extracted plain string from HTML/RTF (trimmed). Pass `nil` when there is no rich payload.
        richPlainText: String?,
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
            if let richPlainText, !richPlainText.isEmpty {
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

    /// Footer under text-like cards.
    public static func characterFooter(forPreviewText previewText: String) -> String {
        let trimmed = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return L10n.tr("clipType.empty", default: "Empty")
        }
        let count = trimmed.utf16.count
        if count == 1 {
            return L10n.tr("clipPreview.oneCharacter", default: "1 character")
        }
        return L10n.tr("clipPreview.characters", default: "%lld characters", count)
    }
}
