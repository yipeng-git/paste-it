import AppKit
import SwiftUI
import PasteItCore

/// Editable NSTextView that preserves HTML / RTF styling.
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var isEditable: Bool = true
    /// Bump to force the text view to become first responder (shows insertion point).
    var focusToken: Int = 0
    var onEditingChanged: ((Bool) -> Void)? = nil

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
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        // Allow typing into attributed runs that carried link / protection attrs.
        textView.enabledTextCheckingTypes = 0
        textView.setAttributedString(attributedText)
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        textView.allowsUndo = isEditable

        let current = textView.attributedString()
        let needsContent = current.isEqual(to: attributedText) == false

        // Always sync external content changes. Skipping while first-responder left the
        // bubble with a caret but empty text after async loadContent + autoFocus.
        if needsContent {
            let selected = textView.selectedRange()
            textView.setAttributedString(attributedText)
            let maxLoc = textView.string.utf16.count
            if selected.location <= maxLoc {
                let maxLen = max(0, maxLoc - selected.location)
                textView.setSelectedRange(NSRange(location: selected.location, length: min(selected.length, maxLen)))
            }
        }

        applyFocusIfNeeded(textView, context: context)
    }

    private func applyFocusIfNeeded(_ textView: NSTextView, context: Context) {
        guard isEditable, focusToken != context.coordinator.lastFocusToken else { return }
        context.coordinator.lastFocusToken = focusToken
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            if !window.isKeyWindow {
                window.makeKey()
            }
            window.makeFirstResponder(textView)
            context.coordinator.parent.onEditingChanged?(true)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        var lastFocusToken: Int = -1

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onEditingChanged?(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEditingChanged?(false)
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
        RichPlainText.attributedString(
            htmlText: item.htmlText,
            rtfData: item.rtfData,
            fallbackPlainText: item.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? item.title
                : item.plainText,
            fontSize: 15
        )
    }

    /// Plain string from HTML/RTF when public.utf8-plain-text was missing on capture.
    static func plainText(htmlText: String?, rtfData: Data?) -> String {
        RichPlainText.extract(htmlText: htmlText, rtfData: rtfData)
    }

    /// HTML/RTF from dark-mode web UIs often ships near-white `foregroundColor`
    /// and display-sized fonts (e.g. `font-size: 28px` headings). On a transparent
    /// liquid-glass bubble that text disappears or dwarfs plain-text previews —
    /// normalize color + type size for on-glass reading.
    static func glassReadable(_ attributed: NSAttributedString, fontSize: CGFloat = 15) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: mutable.length)
        let baseFont = NSFont.systemFont(ofSize: fontSize)
        mutable.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            var next = attrs
            next.removeValue(forKey: .backgroundColor)
            next[.foregroundColor] = NSColor.labelColor
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
                next[.font] = NSFont(descriptor: descriptor, size: fontSize) ?? baseFont
            } else {
                next[.font] = baseFont
            }
            mutable.setAttributes(next, range: range)
        }
        return mutable
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
