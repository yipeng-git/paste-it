import AppKit
import Foundation
import PasteItCore

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
        let fileURLs = Self.collectFileURLs(from: pasteboard, items: pasteboardItems)
        let url = first.string(forType: NSPasteboard.PasteboardType("public.url"))
            .flatMap(URL.init(string:))
            .flatMap { ClipTypeResolver.isWebURL($0) ? $0 : nil }
        let plainText = first.string(forType: .string)
            ?? fileURLs.first?.path
            ?? url?.absoluteString
            ?? ""
        let html = first.string(forType: .html)
        let rtf = first.data(forType: .rtf)
        // Only treat bitmap as image content when this is not a Finder file copy.
        let pngData = fileURLs.isEmpty ? first.data(forType: .png) : nil
        let tiffData = fileURLs.isEmpty ? first.data(forType: .tiff) : nil
        let imageData = pngData ?? tiffData
        let imageExtension = pngData != nil ? "png" : "tiff"

        return PasteboardSnapshot(
            itemCount: pasteboardItems.count,
            types: types,
            fileURLs: fileURLs,
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

    private static func collectFileURLs(
        from pasteboard: NSPasteboard,
        items: [NSPasteboardItem]
    ) -> [URL] {
        var urls: [URL] = []

        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            urls.append(contentsOf: objects.filter(\.isFileURL))
        }

        for item in items {
            if let string = item.string(forType: .fileURL),
               let url = URL(string: string),
               url.isFileURL {
                urls.append(url)
            }
        }

        if let paths = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            urls.append(contentsOf: paths.map { URL(fileURLWithPath: $0) })
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    /// Blob write / thumbnail / hash — safe to run off the main actor.
    private nonisolated static func normalize(
        snapshot: PasteboardSnapshot,
        blobStore: BlobStore
    ) async -> CapturedClip? {
        let fileURLs = snapshot.fileURLs
        let url = snapshot.url
        let plainText = snapshot.plainText
        let html = snapshot.html
        let rtf = snapshot.rtf
        let imageData = snapshot.imageData

        let resolved = ClipTypeResolver.resolve(
            .init(
                fileURLs: fileURLs,
                webURL: url,
                plainText: plainText,
                hasHTML: html?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                hasRTF: rtf?.isEmpty == false,
                hasImageData: imageData != nil
            )
        )
        let primaryType = ClipType(rawValue: resolved.primaryTypeRaw) ?? .text

        guard hasCapturableContent(
            plainText: plainText,
            html: html,
            rtf: rtf,
            fileURLs: fileURLs,
            url: url,
            hasImage: imageData != nil
        ) else {
            return nil
        }

        var blobPath: String?
        var thumbnailPath: String?
        var imagePixelWidth: Int?
        var imagePixelHeight: Int?
        var pendingOCRBlobRelativePath: String?

        // File copies may include a TIFF preview — never promote them to Image.
        if let imageData, fileURLs.isEmpty {
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
        }

        let title = makeTitle(
            primaryType: primaryType,
            plainText: plainText,
            fileURLs: fileURLs,
            webURL: url,
            isDirectory: resolved.isDirectory
        )

        let hashSeed: Data
        if let imageData, fileURLs.isEmpty {
            hashSeed = imageData
        } else if !fileURLs.isEmpty {
            hashSeed = Data(
                (["file"] + resolved.fileURLStrings).joined(separator: "\n").utf8
            )
        } else if let rtf {
            hashSeed = rtf
        } else {
            hashSeed = Data(
                [
                    primaryType.rawValue,
                    plainText,
                    html ?? "",
                    url?.absoluteString ?? ""
                ]
                .joined(separator: "\n")
                .utf8
            )
        }

        let fileURLString: String? = {
            if !resolved.fileURLStrings.isEmpty {
                return resolved.fileURLStrings.joined(separator: "\n")
            }
            if primaryType == .url {
                return url?.absoluteString
            }
            return nil
        }()

        return CapturedClip(
            title: title,
            plainText: plainText,
            htmlText: html,
            rtfData: rtf,
            primaryType: primaryType,
            pasteboardTypes: snapshot.types,
            sourceAppName: snapshot.sourceAppName,
            sourceBundleIdentifier: snapshot.sourceBundleIdentifier,
            blobRelativePath: blobPath,
            thumbnailRelativePath: thumbnailPath,
            fileURLString: fileURLString,
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

    private nonisolated static func hasCapturableContent(
        plainText: String,
        html: String?,
        rtf: Data?,
        fileURLs: [URL],
        url: URL?,
        hasImage: Bool
    ) -> Bool {
        if hasImage || !fileURLs.isEmpty || url != nil { return true }
        if rtf?.isEmpty == false { return true }
        if html?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        return !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private nonisolated static func makeTitle(
        primaryType: ClipType,
        plainText: String,
        fileURLs: [URL],
        webURL: URL?,
        isDirectory: Bool
    ) -> String {
        if fileURLs.count > 1 {
            return "\(fileURLs.count) copied items"
        }
        if let fileURL = fileURLs.first {
            let name = fileURL.lastPathComponent
            if name.isEmpty {
                return fileURL.absoluteString
            }
            if isDirectory, !name.hasSuffix("/") {
                return name
            }
            return name
        }
        if let webURL {
            return webURL.absoluteString
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
    let fileURLs: [URL]
    let url: URL?
    let plainText: String
    let html: String?
    let rtf: Data?
    let imageData: Data?
    let imageExtension: String
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
}
