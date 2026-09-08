import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import PasteItCore

@Suite("Search and media performance regressions")
struct PerformanceRegressionTests {
    private func document(_ text: String, type: String = "text", source: String = "Synthetic Editor",
                          id: UUID = UUID(), revision: Date = .now, date: Date = .now) -> ClipSearchDocument {
        ClipSearchDocument(id: id, revision: revision, type: type, plainText: text,
                           searchText: text, sourceApp: source, createdAt: date)
    }

    @Test func searchPreservesOrderAndSemantics() async throws {
        let index = ClipSearchIndex()
        let docs = [document("Café HELLO"), document("123"), document("hello", type: "image"),
                    document("hello", source: "Other", date: .distantPast)]
        #expect(try await index.search(docs, query: "cafe hello", filter: .all, sourceApp: nil) == [docs[0].id])
        #expect(try await index.search(docs, query: "type:image hello", filter: .all, sourceApp: nil) == [docs[2].id])
        #expect(try await index.search(docs, query: "type:image", filter: .number, sourceApp: nil) == [docs[1].id])
        #expect(try await index.search(docs, query: "hello app:editor date:today", filter: .all, sourceApp: nil) == [docs[0].id, docs[2].id])
        #expect(try await index.search(docs, query: "hello", filter: .all, sourceApp: "Other") == [docs[3].id])
        let counts = try await index.counts(docs, query: "type:image", sourceApp: nil)
        #expect(counts[.all] == 4)
        #expect(counts[.text] == 2)
        #expect(counts[.number] == 1)
        #expect(counts[.image] == 1)
    }

    @Test func editedContentInvalidatesNormalizationAndClassification() async throws {
        let index = ClipSearchIndex()
        let original = document("123", revision: Date(timeIntervalSince1970: 1))
        #expect(try await index.search([original], query: "123", filter: .number, sourceApp: nil) == [original.id])
        let edited = document("changed café", id: original.id, revision: Date(timeIntervalSince1970: 2))
        #expect(try await index.search([edited], query: "123", filter: .all, sourceApp: nil).isEmpty)
        #expect(try await index.search([edited], query: "cafe", filter: .text, sourceApp: nil) == [original.id])
    }

    @Test func cancelledSearchDoesNotPublishPartialResults() async {
        let index = ClipSearchIndex()
        let docs = (0..<5_000).map { document("synthetic item \($0)") }
        let task = Task {
            try Task.checkCancellation()
            return try await index.search(docs, query: "synthetic", filter: .all, sourceApp: nil)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled search unexpectedly returned results")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func boundedCacheEvictsLeastRecentlyUsedAndRejectsOversizeValues() {
        var cache = CostBoundedCache<String, String>(countLimit: 2, costLimit: 8)
        cache.insert("a", for: "a", cost: 4)
        cache.insert("b", for: "b", cost: 4)
        #expect(cache.value(for: "a") == "a")
        cache.insert("c", for: "c", cost: 4)
        #expect(cache.value(for: "b") == nil)
        #expect(cache.value(for: "a") == "a")
        cache.insert("too large", for: "a", cost: 9)
        #expect(cache.value(for: "a") == nil)
        #expect(cache.totalCost == 4)
        cache.insert("c2", for: "c", cost: 2)
        #expect(cache.totalCost == 2)
        #expect(cache.count == 1)
    }

    @Test func imageDecodeBoundsPixelsAndPreservesAspectRatio() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(CGContext(data: nil, width: 2_400, height: 1_200, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let small = try #require(ImageDownsampler.image(at: url, maxPixelSize: 360))
        #expect(small.width == 360)
        #expect(small.height == 180)
        #expect(small.bytesPerRow * small.height < image.bytesPerRow * image.height)
        #expect(ImageDownsampler.image(at: url, maxPixelSize: 0) == nil)
        #expect(ImageDownsampler.image(at: url.appendingPathExtension("missing"), maxPixelSize: 360) == nil)
    }
}

@Suite("Synthetic search benchmarks", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PASTEIT_PERFORMANCE_BENCHMARKS"] == "1"))
struct PerformanceBenchmarks {
    @Test(arguments: [500, 5_000, 20_000])
    func searchScale(count: Int) async throws {
        let revision = Date(timeIntervalSince1970: 1)
        let docs = (0..<count).map { n in
            ClipSearchDocument(id: UUID(), revision: revision, type: "text",
                plainText: "Synthetic café record \(n)",
                searchText: "Synthetic café record \(n) " + String(repeating: "sample body ", count: 20),
                sourceApp: "Synthetic Editor", createdAt: revision)
        }
        let index = ClipSearchIndex()
        let clock = ContinuousClock()
        let startCold = clock.now
        let coldResult = try await index.search(docs, query: "cafe", filter: .text, sourceApp: nil)
        let cold = startCold.duration(to: clock.now)
        #expect(coldResult.count == count)
        let startWarm = clock.now
        for _ in 0..<10 {
            let result = try await index.search(docs, query: "cafe record", filter: .text, sourceApp: nil)
            #expect(result.count == count)
        }
        let warm = startWarm.duration(to: clock.now)
        print("BENCH records=\(count) cold=\(cold) warm10=\(warm)")
    }
}
