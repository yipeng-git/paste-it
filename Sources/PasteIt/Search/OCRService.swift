import AppKit
import Foundation
import ImageIO
import PasteItCore
@preconcurrency import Vision

enum OCRService {
    private static let recognitionQueue = OCRRecognitionQueue()

    static func recognizeText(in image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return await recognizeText(in: cgImage)
    }

    static func recognizeText(in imageData: Data) async -> String? {
        await recognitionQueue.perform {
            let image = autoreleasepool { () -> CGImage? in
                guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
            guard let image else { return nil }
            return await recognizeTextAndTables(in: image)
        }
    }

    private static func recognizeText(in cgImage: CGImage) async -> String? {
        await recognitionQueue.perform {
            await recognizeTextAndTables(in: cgImage)
        }
    }

    private static func recognizeTextAndTables(in cgImage: CGImage) async -> String? {
        let request = VNRecognizeTextRequest()
        // Keep the existing automatic-language OCR as the plain-text fallback.
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> OCRTableText.Line? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return OCRTableText.Line(text: text, bounds: observation.boundingBox)
            }
            guard !lines.isEmpty else { return nil }
            if #available(macOS 26.0, *) {
                let tables = await recognizeTables(in: cgImage, lines: lines)
                return OCRTableText.compose(lines: lines, tables: tables)
            }
            return OCRTableText.compose(lines: lines, tables: [])
        } catch {
            return nil
        }
    }

    @available(macOS 26.0, *)
    private static func recognizeTables(in image: CGImage, lines: [OCRTableText.Line]) async -> [OCRTableText.Table] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = false
        request.barcodeDetectionOptions.enabled = false
        do {
            let documents = try await request.perform(on: image)
            return documents.flatMap { observation in
                observation.document.tables.map { table in
                    let rows = table.rows.indices.map { row in
                        table.columns.indices.map { column in
                            guard let cell = table.cell(row: row, col: column),
                                  cell.rowRange.lowerBound == row,
                                  cell.columnRange.lowerBound == column else { return "" }
                            // A spanning cell appears once, at its top-left anchor.
                            return OCRTableText.cellText(
                                lines: lines, bounds: cell.content.boundingRegion.boundingBox.cgRect,
                                fallback: cell.content.text.transcript
                            )
                        }
                    }
                    return OCRTableText.Table(rows: rows, bounds: table.boundingRegion.boundingBox.cgRect)
                }
            }
        } catch {
            // Detection is optional: a failure must not discard successful text OCR.
            return []
        }
    }
}

/// Keep the complete async Vision pipeline serial without blocking the UI or
/// starting overlapping document-recognition jobs when several images arrive.
private actor OCRRecognitionQueue {
    private var tail: Task<String?, Never>?
    private var latestID = UUID()

    func perform(_ operation: @escaping @Sendable () async -> String?) async -> String? {
        let predecessor = tail
        let id = UUID()
        latestID = id
        let task = Task.detached(priority: .utility) {
            _ = await predecessor?.value
            return await operation()
        }
        tail = task
        let result = await task.value
        if latestID == id { tail = nil }
        return result
    }
}
