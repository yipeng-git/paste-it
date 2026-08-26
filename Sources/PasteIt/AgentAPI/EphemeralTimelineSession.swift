import AppKit
import Foundation
import SwiftUI
import PasteItCore

@MainActor
final class EphemeralTimelineSession {
    private let historyStore: HistoryStore
    private let appState: AppState
    private let tempRoot: URL
    private var panel: NSPanel?
    private let panelHeight: CGFloat = 320
    private let bottomInset: CGFloat = 12

    private init(historyStore: HistoryStore, appState: AppState, tempRoot: URL) {
        self.historyStore = historyStore
        self.appState = appState
        self.tempRoot = tempRoot
    }

    static func create(settings: AppSettings) -> EphemeralTimelineSession {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteItEphemeral-\(UUID().uuidString)", isDirectory: true)
        let store = HistoryStore(ephemeralBlobRoot: tempRoot, settings: settings)
        let appState = AppState(
            settings: settings,
            historyStore: store,
            searchService: SearchService()
        )
        return EphemeralTimelineSession(historyStore: store, appState: appState, tempRoot: tempRoot)
    }

    func seed(cards: [AgentRenderCard], preloadedImages: [Int: Data] = [:]) throws {
        // HistoryStore.add prepends; seed reverse so request order is left-to-right (newest first).
        for (index, card) in cards.enumerated().reversed() {
            let captured = try makeCapturedClip(
                from: card,
                orderIndex: index,
                preloadedImageData: preloadedImages[index]
            )
            historyStore.add(captured)
        }
    }

    /// Shows the real product `TimelineView` over an ephemeral store (does not touch main history).
    func show(query: String, selectedType: ClipType?) {
        if let selectedType,
           let filter = FilterCategory.from(typeToken: selectedType.rawValue) {
            appState.setFilter(filter)
        }

        let view = TimelineView(
            appState: appState,
            pasteController: AppRuntime.shared.pasteController
        )
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Paste It (Agent)"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = hosting
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.ignoresMouseEvents = true

        PanelCornerMask.apply(to: hosting.view)
        PanelCornerMask.apply(to: panel.contentView)

        let frame = targetFrame(for: panel)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        // Apply query after the view is mounted so `searchFocusRequest` activates the field.
        if !query.isEmpty {
            appState.setQueryFromExternal(query)
            appState.searchFocusRequest += 1
        }
    }

    /// Call after settle so search debounce has rebuilt `visibleClips`.
    func finalizeUI(selectedIndex: Int) {
        let clips = appState.visibleClips
        if clips.indices.contains(selectedIndex) {
            appState.selectOnly(clips[selectedIndex].id)
        } else {
            appState.selectFirst()
        }
    }

    func awaitLinkPreviewsIfNeeded() async {
        await historyStore.awaitMissingLinkPreviews()
    }

    var panelFrame: NSRect? {
        panel?.frame
    }

    func tearDown() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        historyStore.destroyEphemeralFiles()
    }

    private func targetFrame(for panel: NSPanel) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width = min(1120, max(640, visibleFrame.width - 32))
        let height = panelHeight
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY + bottomInset,
            width: width,
            height: height
        )
    }

    private func makeCapturedClip(
        from card: AgentRenderCard,
        orderIndex: Int,
        preloadedImageData: Data?
    ) throws -> CapturedClip {
        let type = card.resolvedType
        let plainText = card.plainText ?? ""
        let title = card.title ?? defaultTitle(for: type, plainText: plainText, linkTitle: card.linkTitle)

        var blobRelativePath: String?
        var thumbnailRelativePath: String?
        var imagePixelWidth: Int?
        var imagePixelHeight: Int?
        var contentHashSeed = plainText

        if type == .image {
            let data: Data?
            if let base64 = card.imageBase64 {
                data = Data(base64Encoded: base64)
            } else {
                data = preloadedImageData
            }
            if let data {
                let ingested = try historyStore.ingestImageData(data)
                blobRelativePath = ingested.blobRelativePath
                thumbnailRelativePath = ingested.thumbnailRelativePath
                imagePixelWidth = ingested.pixelWidth
                imagePixelHeight = ingested.pixelHeight
                contentHashSeed = DataHashing.sha256(data)
            }
        }

        let fileURLString: String?
        if type == .url {
            fileURLString = card.fileURLString ?? plainText
        } else if type == .file {
            fileURLString = card.fileURLString ?? plainText
        } else {
            fileURLString = card.fileURLString
        }

        var linkImageRelativePath: String?
        if let linkImageBase64 = card.linkImageBase64, let data = Data(base64Encoded: linkImageBase64) {
            let ingested = try historyStore.ingestImageData(data)
            linkImageRelativePath = ingested.blobRelativePath
        }

        let pasteboardTypes: [String]
        switch type {
        case .image:
            pasteboardTypes = ["public.png"]
        case .url:
            pasteboardTypes = ["public.url", "public.utf8-plain-text"]
        case .file:
            pasteboardTypes = ["public.file-url"]
        default:
            pasteboardTypes = ["public.utf8-plain-text"]
        }

        let hash = DataHashing.sha256("\(contentHashSeed)#\(orderIndex)#\(UUID().uuidString)")

        return CapturedClip(
            title: title,
            plainText: plainText,
            htmlText: card.htmlText,
            rtfData: nil,
            primaryType: type,
            pasteboardTypes: pasteboardTypes,
            sourceAppName: card.sourceAppName,
            sourceBundleIdentifier: card.sourceBundleIdentifier,
            blobRelativePath: blobRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            fileURLString: fileURLString,
            ocrText: card.ocrText,
            linkTitle: card.linkTitle,
            linkIconRelativePath: nil,
            linkImageRelativePath: linkImageRelativePath,
            imagePixelWidth: imagePixelWidth,
            imagePixelHeight: imagePixelHeight,
            contentHash: hash,
            pendingOCRBlobRelativePath: nil
        )
    }

    private func defaultTitle(for type: ClipType, plainText: String, linkTitle: String?) -> String {
        if let linkTitle, !linkTitle.isEmpty { return linkTitle }
        switch type {
        case .image: return "Image"
        case .url: return "Link"
        case .file:
            if let name = URL(string: plainText)?.lastPathComponent, !name.isEmpty { return name }
            return "File"
        default:
            let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return type.title }
            return String(trimmed.prefix(48))
        }
    }
}

struct AgentRenderCard: Decodable {
    let type: String?
    let title: String?
    let plainText: String?
    let htmlText: String?
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
    let ocrText: String?
    let linkTitle: String?
    let fileURLString: String?
    let imageBase64: String?
    let imagePath: String?
    let linkImageBase64: String?

    var resolvedType: ClipType {
        if let type {
            let normalized = type.lowercased()
            if normalized == "link" { return .url }
            if let parsed = ClipType(rawValue: normalized) {
                return parsed
            }
        }
        if imageBase64 != nil || imagePath != nil { return .image }
        if let text = plainText ?? fileURLString,
           let url = URL(string: text),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return .url
        }
        return .text
    }
}
