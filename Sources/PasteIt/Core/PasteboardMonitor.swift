import AppKit
import Foundation

@MainActor
final class PasteboardMonitor: NSObject {
    private let pasteboard = NSPasteboard.general
    private let settings: AppSettings
    private let blobStore: BlobStore
    private let historyStore: HistoryStore
    private let pasteStackController: PasteStackController

    private var timer: Timer?
    private var lastChangeCount: Int
    private var suppressedChangeCounts = Set<Int>()
    private var isCapturing = false

    init(
        settings: AppSettings,
        blobStore: BlobStore,
        historyStore: HistoryStore,
        pasteStackController: PasteStackController
    ) {
        self.settings = settings
        self.blobStore = blobStore
        self.historyStore = historyStore
        self.pasteStackController = pasteStackController
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        let interval = settings.clipboardCheckInterval
        // Block timer avoids @objc → @MainActor isolation checks that were crashing
        // (EXC_BAD_ACCESS in swift_task_isCurrentExecutor / objc_opt_class).
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForChanges()
            }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func suppress(changeCount: Int) {
        suppressedChangeCounts.insert(changeCount)
        lastChangeCount = changeCount
    }

    private func checkForChanges() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if suppressedChangeCounts.remove(current) != nil {
            return
        }
        guard !settings.capturePaused, !isCapturing else { return }

        // Snapshot pasteboard on the main thread (NSPasteboard is main-thread affinity),
        // then finish heavy work off-main.
        guard let snapshot = snapshotPasteboard() else { return }

        isCapturing = true
        Task {
            let captured = await Self.normalize(
                snapshot: snapshot,
                blobStore: blobStore
            )
            await MainActor.run {
                if let captured {
                    historyStore.add(captured)
                    if pasteStackController.isCollecting {
                        pasteStackController.append(captured)
                    }
                }
                self.isCapturing = false
            }
        }
    }

    /// Lightweight pasteboard read — stays on the main actor.
    private func snapshotPasteboard() -> PasteboardSnapshot? {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            return nil
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication
        guard !settings.isIgnored(bundleIdentifier: sourceApp?.bundleIdentifier) else {
            return nil
        }

        let rawTypes = pasteboardItems.flatMap { item in item.types.map(\.rawValue) }
        guard !rawTypes.contains(where: settings.ignoresPasteboardType) else {
            return nil
        }

        let first = pasteboardItems[0]
        let types = Array(Set(pasteboardItems.flatMap { $0.types.map(\.rawValue) })).sorted()
        let fileURL = first.string(forType: .fileURL).flatMap(URL.init(string:))
        let url = first.string(forType: NSPasteboard.PasteboardType("public.url")).flatMap(URL.init(string:))
        let plainText = first.string(forType: .string) ?? fileURL?.path ?? url?.absoluteString ?? ""
        let html = first.string(forType: .html)
        let rtf = first.data(forType: .rtf)
        let pngData = first.data(forType: .png)
        let tiffData = first.data(forType: .tiff)
        let imageData = pngData ?? tiffData
        let imageExtension = pngData != nil ? "png" : "tiff"

        return PasteboardSnapshot(
            itemCount: pasteboardItems.count,
            types: types,
            fileURL: fileURL,
            url: url,
            plainText: plainText,
            html: html,
            rtf: rtf,
            imageData: imageData,
            imageExtension: imageExtension,
            sourceAppName: sourceApp?.localizedName,
            sourceBundleIdentifier: sourceApp?.bundleIdentifier
        )
    }

    /// Blob write / thumbnail / hash — safe to run off the main actor.
    private nonisolated static func normalize(
        snapshot: PasteboardSnapshot,
        blobStore: BlobStore
    ) async -> CapturedClip? {
        let fileURL = snapshot.fileURL
        let url = snapshot.url
        let plainText = snapshot.plainText
        let html = snapshot.html
        let rtf = snapshot.rtf
        let imageData = snapshot.imageData

        var blobPath: String?
        var thumbnailPath: String?
        var imagePixelWidth: Int?
        var imagePixelHeight: Int?
        var primaryType = determinePrimaryType(
            fileURL: fileURL,
            url: url,
            plainText: plainText,
            html: html,
            rtf: rtf,
            hasImage: imageData != nil
        )

        guard hasCapturableContent(
            plainText: plainText,
            html: html,
            rtf: rtf,
            fileURL: fileURL,
            url: url,
            hasImage: imageData != nil
        ) else {
            return nil
        }

        var pendingOCRBlobRelativePath: String?
        if let imageData {
            let imageID = UUID()
            blobPath = try? blobStore.store(
                data: imageData,
                preferredExtension: snapshot.imageExtension,
                id: imageID
            )
            if let thumb = try? blobStore.storeThumbnail(fromImageData: imageData, id: imageID) {
                thumbnailPath = thumb.path
                if thumb.pixelWidth > 0, thumb.pixelHeight > 0 {
                    imagePixelWidth = thumb.pixelWidth
                    imagePixelHeight = thumb.pixelHeight
                }
            }
            pendingOCRBlobRelativePath = blobPath
            primaryType = .image
        }

        let title = makeTitle(
            primaryType: primaryType,
            plainText: plainText,
            fileURL: fileURL ?? url,
            itemCount: snapshot.itemCount
        )

        let hashSeed: Data
        if let imageData {
            hashSeed = imageData
        } else if let rtf {
            hashSeed = rtf
        } else {
            hashSeed = Data(
                [
                    primaryType.rawValue,
                    plainText,
                    html ?? "",
                    fileURL?.absoluteString ?? "",
                    url?.absoluteString ?? ""
                ]
                .joined(separator: "\n")
                .utf8
            )
        }

        return CapturedClip(
            title: title,
            plainText: plainText,
            htmlText: html,
            rtfData: rtf,
            primaryType: snapshot.itemCount > 1 ? .mixed : primaryType,
            pasteboardTypes: snapshot.types,
            sourceAppName: snapshot.sourceAppName,
            sourceBundleIdentifier: snapshot.sourceBundleIdentifier,
            blobRelativePath: blobPath,
            thumbnailRelativePath: thumbnailPath,
            fileURLString: (fileURL ?? url)?.absoluteString,
            ocrText: nil,
            linkTitle: nil,
            linkIconRelativePath: nil,
            linkImageRelativePath: nil,
            imagePixelWidth: imagePixelWidth,
            imagePixelHeight: imagePixelHeight,
            contentHash: DataHashing.sha256(hashSeed),
            pendingOCRBlobRelativePath: pendingOCRBlobRelativePath
        )
    }

    private nonisolated static func determinePrimaryType(
        fileURL: URL?,
        url: URL?,
        plainText: String,
        html: String?,
        rtf: Data?,
        hasImage: Bool
    ) -> ClipType {
        if hasImage { return .image }
        if fileURL != nil { return .file }
        if url != nil || plainText.looksLikeURL { return .url }
        if rtf != nil { return .richText }
        if html != nil { return .html }
        return .text
    }

    private nonisolated static func hasCapturableContent(
        plainText: String,
        html: String?,
        rtf: Data?,
        fileURL: URL?,
        url: URL?,
        hasImage: Bool
    ) -> Bool {
        if hasImage || fileURL != nil || url != nil { return true }
        if rtf?.isEmpty == false { return true }
        if html?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        return !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private nonisolated static func makeTitle(
        primaryType: ClipType,
        plainText: String,
        fileURL: URL?,
        itemCount: Int
    ) -> String {
        if itemCount > 1 {
            return "\(itemCount) copied items"
        }
        if let fileURL {
            return fileURL.lastPathComponent.isEmpty ? fileURL.absoluteString : fileURL.lastPathComponent
        }
        let trimmed = plainText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return String(trimmed.prefix(80))
        }
        return primaryType.title
    }
}

/// Immutable pasteboard snapshot that can leave the main actor.
private struct PasteboardSnapshot: Sendable {
    let itemCount: Int
    let types: [String]
    let fileURL: URL?
    let url: URL?
    let plainText: String
    let html: String?
    let rtf: Data?
    let imageData: Data?
    let imageExtension: String
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
}
