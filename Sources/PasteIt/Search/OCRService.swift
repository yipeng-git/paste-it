import AppKit
import Foundation
import ImageIO
@preconcurrency import Vision

enum OCRService {
    // Bound Vision work when several images arrive together. Capture and history
    // insertion do not wait for this queue; OCR updates the searchable clip later.
    private static let recognitionQueue = DispatchQueue(label: "app.pasteit.ocr", qos: .utility)

    static func recognizeText(in image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return await recognizeText(in: cgImage)
    }

    static func recognizeText(in imageData: Data) async -> String? {
        await withCheckedContinuation { continuation in
            recognitionQueue.async {
                let text: String? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                        return nil
                    }
                    return recognizeTextSynchronously(in: cgImage)
                }
                continuation.resume(returning: text)
            }
        }
    }

    private static func recognizeText(in cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            recognitionQueue.async {
                let text = autoreleasepool {
                    recognizeTextSynchronously(in: cgImage)
                }
                continuation.resume(returning: text)
            }
        }
    }

    /// Runs only on recognitionQueue. A synchronous request has a single result
    /// path, including Vision errors, so the continuation is resumed exactly once.
    private static func recognizeTextSynchronously(in cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        // Clipboard images can contain any language. Let Vision choose its model
        // instead of restricting recognition to a fixed language list.
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
