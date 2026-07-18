import AppKit
import SwiftUI

/// Editable NSTextView that preserves HTML / RTF styling.
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = isEditable
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.setAttributedString(attributedText)
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Don't clobber in-progress edits; coordinator pushes changes outward.
        guard textView.window?.firstResponder !== textView else { return }
        if textView.attributedString().isEqual(to: attributedText) == false {
            textView.setAttributedString(attributedText)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.attributedText = textView.attributedString()
        }
    }
}

extension NSTextView {
    func setAttributedString(_ attributedString: NSAttributedString) {
        textStorage?.setAttributedString(attributedString)
    }

    func attributedString() -> NSAttributedString {
        textStorage.map { NSAttributedString(attributedString: $0) } ?? NSAttributedString(string: string)
    }
}

enum RichTextCodec {
    /// Full fidelity for the editor.
    static func attributedString(from item: ClipItem) -> NSAttributedString {
        attributedString(
            htmlText: item.htmlText,
            rtfData: item.rtfData,
            fallbackPlainText: item.previewText,
            fontSize: 15
        )
    }

    private static func attributedString(
        htmlText: String?,
        rtfData: Data?,
        fallbackPlainText: String,
        fontSize: CGFloat
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

    static func plainText(from attributed: NSAttributedString) -> String {
        attributed.string
    }

    static func html(from attributed: NSAttributedString) -> String? {
        guard attributed.length > 0 else { return nil }
        let range = NSRange(location: 0, length: attributed.length)
        guard let data = try? attributed.data(
            from: range,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func rtf(from attributed: NSAttributedString) -> Data? {
        guard attributed.length > 0 else { return nil }
        let range = NSRange(location: 0, length: attributed.length)
        return try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
