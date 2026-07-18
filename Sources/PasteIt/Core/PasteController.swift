import AppKit
import Foundation

@MainActor
final class PasteController {
    enum PasteMode {
        case normal
        case plainText
    }

    var onPasteboardMutation: ((Int) -> Void)?

    private let blobStore: BlobStore

    init(blobStore: BlobStore) {
        self.blobStore = blobStore
    }

    /// Stages a clip onto the system pasteboard, replacing the previous clipboard contents.
    /// Does not synthesize Command+V; the user pastes manually in the target app.
    @discardableResult
    func copyToPasteboard(_ item: ClipItem, mode: PasteMode = .normal) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let wrote = write(item, to: pasteboard, mode: mode, preloadedImageData: nil)
        onPasteboardMutation?(pasteboard.changeCount)
        return wrote
    }

    /// Async variant that reads large image blobs off the main thread before writing.
    @discardableResult
    func copyToPasteboardAsync(_ item: ClipItem, mode: PasteMode = .normal) async -> Bool {
        var preloaded: Data?
        if mode == .normal, item.primaryType == .image {
            let path = item.blobRelativePath
            let store = blobStore
            preloaded = await Task.detached(priority: .userInitiated) {
                store.data(for: path)
            }.value
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let wrote = write(item, to: pasteboard, mode: mode, preloadedImageData: preloaded)
        onPasteboardMutation?(pasteboard.changeCount)
        return wrote
    }

    /// Stages multiple clips as combined plain text on the system pasteboard.
    @discardableResult
    func copyToPasteboard(_ items: [ClipItem], mode: PasteMode = .normal) -> Bool {
        guard !items.isEmpty else { return false }
        if items.count == 1, let item = items.first {
            return copyToPasteboard(item, mode: mode)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let combined = items.map(\.previewText).joined(separator: "\n")
        let wrote = pasteboard.setString(combined, forType: .string)
        onPasteboardMutation?(pasteboard.changeCount)
        return wrote
    }

    private func write(
        _ item: ClipItem,
        to pasteboard: NSPasteboard,
        mode: PasteMode,
        preloadedImageData: Data?
    ) -> Bool {
        if mode == .plainText {
            return pasteboard.setString(item.previewText, forType: .string)
        }

        switch item.primaryType {
        case .image:
            let pasteboardItem = NSPasteboardItem()
            let data = preloadedImageData ?? blobStore.data(for: item.blobRelativePath)
            if let data {
                let type: NSPasteboard.PasteboardType = item.blobRelativePath?.hasSuffix(".tiff") == true ? .tiff : .png
                pasteboardItem.setData(data, forType: type)
            }
            if !item.plainText.isEmpty {
                pasteboardItem.setString(item.plainText, forType: .string)
            }
            return pasteboard.writeObjects([pasteboardItem])
        case .file:
            if let fileURLString = item.fileURLString,
               let url = URL(string: fileURLString) {
                return pasteboard.writeObjects([url as NSURL])
            }
            return pasteboard.setString(item.previewText, forType: .string)
        case .html, .richText, .mixed, .url, .text:
            let pasteboardItem = NSPasteboardItem()
            if !item.plainText.isEmpty {
                pasteboardItem.setString(item.plainText, forType: .string)
            }
            if let htmlText = item.htmlText {
                pasteboardItem.setString(htmlText, forType: .html)
            }
            if let rtfData = item.rtfData {
                pasteboardItem.setData(rtfData, forType: .rtf)
            }
            if let fileURLString = item.fileURLString, item.primaryType == .url {
                pasteboardItem.setString(fileURLString, forType: NSPasteboard.PasteboardType("public.url"))
            }
            return pasteboard.writeObjects([pasteboardItem])
        }
    }
}
