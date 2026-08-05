import AppKit
import Foundation

/// Extracts plain strings from HTML / RTF clipboard payloads (AppKit).
public enum RichPlainText: Sendable {
    public static func extract(htmlText: String?, rtfData: Data?) -> String {
        attributedString(htmlText: htmlText, rtfData: rtfData, fallbackPlainText: "")
            .string
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func attributedString(
        htmlText: String?,
        rtfData: Data?,
        fallbackPlainText: String,
        fontSize: CGFloat = 15
    ) -> NSAttributedString {
        if let rtfData,
           let attributed = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
           ),
           attributed.length > 0 {
            return attributed
        }

        if let htmlText,
           let data = htmlText.data(using: .utf8) ?? htmlText.data(using: .utf16),
           let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
           ),
           attributed.length > 0 {
            return attributed
        }

        return NSAttributedString(
            string: fallbackPlainText,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }
}
