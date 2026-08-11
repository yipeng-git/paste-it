import AppKit
import Foundation

enum RenderScreenshotHandler {
    /// Reject huge agent-supplied images so MainActor / memory don't melt.
    static let maxImageBytes = 25 * 1024 * 1024

    @MainActor private static var isRendering = false

    struct Request: Decodable {
        let cards: [AgentRenderCard]
        let ui: UI?
        let outputPath: String?

        struct UI: Decodable {
            let query: String?
            let selectedType: String?
            let selectedIndex: Int?
        }
    }

    struct Response: Encodable {
        let path: String
        let width: Int
        let height: Int
    }

    enum HandlerError: LocalizedError, Equatable {
        case emptyCards
        case invalidOutputPath
        case imageTooLarge(path: String, bytes: Int)
        case captureFailed(String)
        case busy

        var errorDescription: String? {
            switch self {
            case .emptyCards:
                return "cards must be a non-empty array"
            case .invalidOutputPath:
                return "outputPath must be an absolute local path"
            case .imageTooLarge(let path, let bytes):
                return "imagePath too large (\(bytes) bytes, max \(maxImageBytes)): \(path)"
            case .captureFailed(let message):
                return message
            case .busy:
                return "Another render_screenshot is in progress; retry shortly"
            }
        }
    }

    @MainActor
    static func handle(_ request: Request, settings: AppSettings) async throws -> Response {
        guard !isRendering else { throw HandlerError.busy }
        isRendering = true
        defer { isRendering = false }

        guard !request.cards.isEmpty else { throw HandlerError.emptyCards }

        let outputURL = try resolveOutputURL(request.outputPath)
        let query = request.ui?.query ?? ""
        let selectedType = request.ui?.selectedType.flatMap { ClipType(rawValue: $0) }
        let selectedIndex = request.ui?.selectedIndex ?? 0

        // Preload image files off the main actor before building UI.
        let preloaded = try await preloadCardImages(request.cards)

        let session = EphemeralTimelineSession.create(settings: settings)
        defer { session.tearDown() }

        try session.seed(cards: request.cards, preloadedImages: preloaded)

        let hasLinks = request.cards.contains { $0.resolvedType == .url && $0.linkImageBase64 == nil }
        if hasLinks {
            // Fetch OG/favicon before showing so the first paint already has preview art.
            await session.awaitLinkPreviewsIfNeeded()
        }

        session.show(query: query, selectedType: selectedType)

        // Yield + sleep releases MainActor so health / menu stay responsive during wait.
        await Task.yield()
        await Task.yield()
        let hasImages = request.cards.contains { $0.resolvedType == .image }
        let settleNs: UInt64
        if hasLinks {
            settleNs = 450_000_000
        } else if hasImages {
            settleNs = 550_000_000
        } else {
            settleNs = 350_000_000
        }
        try await Task.sleep(nanoseconds: settleNs)

        // After search debounce / first paint, lock selection then capture.
        session.finalizeUI(selectedIndex: selectedIndex)
        await Task.yield()

        guard let frame = session.panelFrame else {
            throw HandlerError.captureFailed("Ephemeral panel has no frame")
        }

        do {
            try await ScreenRegionCapture.capture(frame, to: outputURL)
        } catch {
            throw HandlerError.captureFailed(error.localizedDescription)
        }

        let pixelSize = await Task.detached(priority: .utility) {
            NSImage(contentsOf: outputURL)?.size
        }.value
        let size = pixelSize ?? NSSize(width: frame.width, height: frame.height)

        return Response(
            path: outputURL.path,
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded())
        )
    }

    private static func preloadCardImages(_ cards: [AgentRenderCard]) async throws -> [Int: Data] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: [Int: Data] = [:]
                do {
                    for (index, card) in cards.enumerated() {
                        guard card.resolvedType == .image, let path = card.imagePath, card.imageBase64 == nil else {
                            continue
                        }
                        let url = URL(fileURLWithPath: path)
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        if let size = values.fileSize, size > maxImageBytes {
                            throw HandlerError.imageTooLarge(path: path, bytes: size)
                        }
                        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                        if data.count > maxImageBytes {
                            throw HandlerError.imageTooLarge(path: path, bytes: data.count)
                        }
                        result[index] = data
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func resolveOutputURL(_ outputPath: String?) throws -> URL {
        if let outputPath {
            guard outputPath.hasPrefix("/") else { throw HandlerError.invalidOutputPath }
            return URL(fileURLWithPath: outputPath)
        }

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PasteIt", isDirectory: true)
            .appendingPathComponent("AgentScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        var name = "render-\(formatter.string(from: Date())).png"
        var url = dir.appendingPathComponent(name)
        var suffix = 1
        while FileManager.default.fileExists(atPath: url.path) {
            name = "render-\(formatter.string(from: Date()))-\(suffix).png"
            url = dir.appendingPathComponent(name)
            suffix += 1
        }
        return url
    }
}
