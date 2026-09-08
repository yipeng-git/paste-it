import AppKit
import Foundation
import ImageIO
import PasteItCore

@MainActor
final class PasteController {
    enum PasteMode {
        case normal
        case plainText
    }

    var onPasteboardMutation: ((Int) -> Void)?

    private let blobStore: BlobStore
    private let pasteboard: NSPasteboard

    init(blobStore: BlobStore, pasteboard: NSPasteboard = .general) {
        self.blobStore = blobStore
        self.pasteboard = pasteboard
    }

    /// Stages a clip onto the system pasteboard, replacing the previous clipboard contents.
    /// Does not synthesize Command+V; the user pastes manually in the target app.
    @discardableResult
    func copyToPasteboard(_ item: ClipItem, mode: PasteMode = .normal) -> Bool {
        guard let objects = preparedObjects(item, mode: mode, imageData: nil) else { return false }
        return replaceContents(with: objects)
    }

    /// Prepare the image before touching the user's clipboard.
    @discardableResult
    func copyToPasteboardAsync(_ item: ClipItem, mode: PasteMode = .normal) async -> Bool {
        if mode != .normal || item.primaryType != .image {
            return copyToPasteboard(item, mode: mode)
        }
        let path = item.blobRelativePath
        let store = blobStore
        guard let data = await Task.detached(priority: .userInitiated, operation: {
            store.data(for: path)
        }).value else { return false }
        guard !Task.isCancelled,
              let objects = preparedObjects(item, mode: mode, imageData: data) else { return false }
        return replaceContents(with: objects)
    }

    /// Roll back a failed write and suppress both the attempt and restoration.
    private func replaceContents(with objects: [NSPasteboardWriting]) -> Bool {
        let snapshot = snapshotGeneralPasteboard()
        pasteboard.clearContents()
        defer { onPasteboardMutation?(pasteboard.changeCount) }
        if pasteboard.writeObjects(objects) { return true }
        if let snapshot { _ = restoreGeneralPasteboard(snapshot) }
        return false
    }

    /// Stages multiple clips as combined plain text on the system pasteboard.
    @discardableResult
    func copyToPasteboard(_ items: [ClipItem], mode: PasteMode = .normal) -> Bool {
        guard !items.isEmpty else { return false }
        if items.count == 1, let item = items.first {
            return copyToPasteboard(item, mode: mode)
        }

        pasteboard.clearContents()
        let combined = items.map(\.previewText).joined(separator: "\n")
        let wrote = pasteboard.setString(combined, forType: .string)
        onPasteboardMutation?(pasteboard.changeCount)
        return wrote
    }

    /// Deep-copies every pasteboard item/type so we can restore after a temporary rewrite.
    func snapshotGeneralPasteboard() -> GeneralPasteboardSnapshot? {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            return nil
        }

        var items: [GeneralPasteboardSnapshot.Item] = []
        for pasteboardItem in pasteboardItems {
            var entries: [GeneralPasteboardSnapshot.Entry] = []
            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type), !data.isEmpty else { continue }
                entries.append(.init(type: type, data: data))
            }
            if !entries.isEmpty {
                items.append(.init(entries: entries))
            }
        }
        return items.isEmpty ? nil : GeneralPasteboardSnapshot(items: items)
    }

    /// Plain string currently on the general pasteboard (derives from HTML/RTF when needed).
    func plainTextFromGeneralPasteboard() -> String? {
        let item = pasteboard.pasteboardItems?.first
        var plain = item?.string(forType: .string) ?? pasteboard.string(forType: .string) ?? ""
        if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let html = item?.string(forType: .html) ?? pasteboard.string(forType: .html)
            let rtf = item?.data(forType: .rtf) ?? pasteboard.data(forType: .rtf)
            plain = RichPlainText.extract(htmlText: html, rtfData: rtf)
        }
        return plain.isEmpty ? nil : plain
    }

    /// Writes plain text only. Marks transient so other clipboard managers can ignore the blip.
    @discardableResult
    func writePlainTextToGeneralPasteboard(_ plain: String, markTransient: Bool = true) -> Bool {
        guard !plain.isEmpty else { return false }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(plain, forType: .string)
        if markTransient {
            item.setString("", forType: .init("org.nspasteboard.TransientType"))
        }
        guard pasteboard.writeObjects([item]) else { return false }
        onPasteboardMutation?(pasteboard.changeCount)
        return true
    }

    /// Restores a prior deep snapshot onto the general pasteboard.
    @discardableResult
    func restoreGeneralPasteboard(_ snapshot: GeneralPasteboardSnapshot) -> Bool {
        pasteboard.clearContents()
        let objects: [NSPasteboardItem] = snapshot.items.map { item in
            let pasteboardItem = NSPasteboardItem()
            for entry in item.entries {
                pasteboardItem.setData(entry.data, forType: entry.type)
            }
            return pasteboardItem
        }
        guard pasteboard.writeObjects(objects) else { return false }
        onPasteboardMutation?(pasteboard.changeCount)
        return true
    }

    private func preparedObjects(
        _ item: ClipItem,
        mode: PasteMode,
        imageData: Data?
    ) -> [NSPasteboardWriting]? {
        if mode == .plainText {
            let text: String
            if item.primaryType == .image { text = item.ocrText ?? item.plainText }
            else { text = item.previewText }
            guard !text.isEmpty else { return nil }
            return [text as NSString]
        }

        let result = NSPasteboardItem()
        switch item.primaryType {
        case .image:
            guard let data = imageData ?? blobStore.data(for: item.blobRelativePath),
                  CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
            let type: NSPasteboard.PasteboardType = item.blobRelativePath?.hasSuffix(".tiff") == true ? .tiff : .png
            result.setData(data, forType: type)
            if !item.plainText.isEmpty { result.setString(item.plainText, forType: .string) }
        case .file:
            let urls = item.storedFileURLs
            guard !urls.isEmpty,
                  urls.allSatisfy({ $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
            return urls as [NSURL]
        case .html, .richText, .mixed, .url, .text:
            if !item.plainText.isEmpty { result.setString(item.plainText, forType: .string) }
            if let html = item.htmlText, !html.isEmpty { result.setString(html, forType: .html) }
            if let rtf = item.rtfData, !rtf.isEmpty { result.setData(rtf, forType: .rtf) }
            if let url = item.fileURLString, item.primaryType == .url {
                result.setString(url, forType: .init("public.url"))
            }
        }
        guard !result.types.isEmpty else { return nil }
        return [result]
    }

}

/// Raw pasteboard bytes for temporary rewrite → restore (⌃⌘V).
struct GeneralPasteboardSnapshot: Sendable {
    struct Entry: Sendable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    struct Item: Sendable {
        let entries: [Entry]
    }

    let items: [Item]
}
