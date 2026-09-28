import AppKit
import Foundation
import Testing
@testable import PasteIt

private struct OCRSample: Sendable {
    let text: String
    let keywords: [String]
    var fontName: String = "PingFangSC-Regular"

    static let multilingual = [
        OCRSample(text: "星河 4821 简体中文搜索", keywords: ["星河", "简体中文搜索"]),
        OCRSample(text: "星河 4821 繁體中文搜尋", keywords: ["星河", "繁體中文搜尋"], fontName: "PingFangTC-Regular"),
        OCRSample(text: "Clipboard 星河 中文截图搜索 4821", keywords: ["星河", "Clipboard", "截图搜索"]),
        OCRSample(text: "Clipboard history search 4821", keywords: ["Clipboard", "history"]),
        OCRSample(text: "クリップボード 履歴検索 4821", keywords: ["クリップボード", "履歴検索"], fontName: "HiraginoSans-W3"),
        OCRSample(text: "클립보드 기록 검색 4821", keywords: ["클립보드", "검색"], fontName: "AppleSDGothicNeo-Regular"),
        OCRSample(text: "Clipboard クリップボード 4821", keywords: ["Clipboard", "クリップボード"], fontName: "HiraginoSans-W3")
    ]
}

@MainActor
@Suite("OCR image indexing", .serialized)
struct OCRServiceTests {
    /// Draw a deterministic, high-contrast raster without reading the clipboard or user files.
    private func png(text: String, fontName: String = "PingFangSC-Regular") throws -> Data {
        let size = NSSize(width: 1200, height: 180)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let font = NSFont(name: fontName, size: 48)
            ?? NSFont.systemFont(ofSize: 48)
        (text as NSString).draw(at: NSPoint(x: 40, y: 60), withAttributes: [
            .font: font,
            .foregroundColor: NSColor.black
        ])
        context.flushGraphics()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func compact(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    @Test(arguments: OCRSample.multilingual)
    fileprivate func automaticallyRecognizesMultipleLanguages(_ sample: OCRSample) async throws {
        let data = try png(text: sample.text, fontName: sample.fontName)
        let text = try #require(await OCRService.recognizeText(in: data))
        let recognized = compact(text)
        // Vision may insert spaces around CJK characters; those are not search regressions.
        #expect(recognized.contains("4821"))
        for keyword in sample.keywords {
            #expect(recognized.contains(keyword))
        }
    }

    @Test func sparseChineseInEnglishHasKnownSystemDetectionLimitation() async throws {
        let data = try png(text: "Clipboard 星河 4821 Search")
        let text = try #require(await OCRService.recognizeText(in: data))
        #expect(text.contains("Clipboard"))
        #expect(text.contains("4821"))
        // Keep the previous mixed-language fixture visible: automatic detection
        // can choose the Latin model even with confidence 1.0 on macOS 26.6.2.
        // More Chinese context passes above. Allow future Vision models to fix it.
        withKnownIssue("Vision automatic language detection can miss sparse Chinese in an English line", isIntermittent: true) {
            #expect(compact(text).contains("星河"))
        }
    }

    @Test func blankAndInvalidImagesReturnNoText() async throws {
        let blank = try png(text: "")
        #expect(await OCRService.recognizeText(in: blank) == nil)
        #expect(await OCRService.recognizeText(in: Data()) == nil)
        #expect(await OCRService.recognizeText(in: Data("not an image".utf8)) == nil)
        let valid = try png(text: "Synthetic 4821")
        #expect(await OCRService.recognizeText(in: Data(valid.prefix(24))) == nil)
    }

    @Test func concurrentRequestsKeepTheirOwnImageResults() async throws {
        let labels = ["ALPHA 4821", "BRAVO 7396", "DELTA 8652"]
        let inputs = try labels.enumerated().map { (index: $0.offset, data: try png(text: $0.element)) }
        let results = await withTaskGroup(of: (Int, String?).self) { group in
            for input in inputs {
                group.addTask {
                    (input.index, await OCRService.recognizeText(in: input.data))
                }
            }
            var results: [Int: String] = [:]
            for await (index, text) in group {
                if let text { results[index] = text }
            }
            return results
        }
        #expect(results.count == labels.count)
        for (index, label) in labels.enumerated() {
            let text = try #require(results[index])
            #expect(compact(text).contains(compact(label)))
            for other in labels.indices where other != index {
                #expect(!compact(text).contains(compact(labels[other])))
            }
        }
    }

    @Test func rerunUpdatesPreviouslyCachedImageSearchResults() async throws {
        let suite = "PasteIt-OCR-Tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteItEphemeral-OCR-\(UUID())")
        let store = HistoryStore(ephemeralBlobRoot: root, settings: settings)
        defer {
            store.destroyEphemeralFiles()
            defaults.removePersistentDomain(forName: suite)
        }
        let data = try png(text: "星河 4821 中文搜索")
        let item = ClipItem(title: "Synthetic screenshot", primaryType: .image,
                            pasteboardTypes: [], contentHash: "synthetic-ocr-image")
        item.blobRelativePath = try store.blobStore.store(data: data, preferredExtension: "png")
        store.context.insert(item)
        try store.context.save()
        store.refresh()

        let state = AppState(settings: settings, historyStore: store, searchService: SearchService())
        state.setQueryFromExternal("星河")
        await state.awaitSearchResults()
        #expect(state.visibleClips.isEmpty)
        #expect(store.searchDocuments(for: [item]).first?.searchText.contains("星河") == false)

        await store.rerunOCR(for: item)
        // HistoryStore coalesces notifications on the next main-queue turn.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        await state.awaitSearchResults()

        let recognized = try #require(item.ocrText)
        #expect(compact(recognized).contains("星河"))
        #expect(store.searchDocuments(for: [item]).first?.searchText.contains("星河") == true)
        #expect(state.visibleClips.map(\.id) == [item.id])
    }
}
