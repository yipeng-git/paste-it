import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenRegionCapture {
    enum CaptureError: LocalizedError {
        case noScreen
        case processFailed(Int32, String)
        case cgCaptureFailed
        case missingOutput
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noScreen:
                return "No screen available for capture"
            case .processFailed(let code, let stderr):
                let detail = stderr.isEmpty ? "" : ": \(stderr)"
                return "screencapture exited with status \(code)\(detail)"
            case .cgCaptureFailed:
                return "CoreGraphics screen-region capture failed"
            case .missingOutput:
                return "Screenshot file was not created"
            case .writeFailed:
                return "Failed to write PNG"
            }
        }
    }

    /// Captures a Cocoa-coordinate rect as composited screen pixels (includes Liquid Glass refraction).
    /// Heavy work (CLI fallback) runs off the main thread so the Agent API stays responsive.
    static func capture(_ cocoaRect: NSRect, to url: URL) async throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        // CG capture must happen with a stable frame; keep it brief on whatever thread we're on.
        if try captureWithCoreGraphics(cocoaRect, to: url) {
            return
        }

        // Never call Process.waitUntilExit on the main actor — it can deadlock the app
        // (and freeze Agent API / menu) when screencapture needs WindowServer.
        try await captureWithScreencaptureOffMain(cocoaRect, to: url)
    }

    private static func captureWithCoreGraphics(_ cocoaRect: NSRect, to url: URL) throws -> Bool {
        let quartz = cocoaToQuartzRect(cocoaRect)
        let cgRect = CGRect(
            x: CGFloat(quartz.x),
            y: CGFloat(quartz.y),
            width: CGFloat(quartz.width),
            height: CGFloat(quartz.height)
        )
        let image: CGImage? = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
        guard let image else { return false }
        try writePNG(image, to: url)
        return true
    }

    private static func captureWithScreencaptureOffMain(_ cocoaRect: NSRect, to url: URL) async throws {
        let quartz = cocoaToQuartzRect(cocoaRect)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try runScreencapture(quartz: quartz, to: url)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runScreencapture(
        quartz: (x: Int, y: Int, width: Int, height: Int),
        to url: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [
            "-x",
            "-R\(quartz.x),\(quartz.y),\(quartz.width),\(quartz.height)",
            url.path
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw CaptureError.processFailed(process.terminationStatus, errText)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CaptureError.missingOutput
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.writeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw CaptureError.writeFailed
        }
    }

    private static func cocoaToQuartzRect(_ rect: NSRect) -> (x: Int, y: Int, width: Int, height: Int) {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let primaryHeight = primary?.frame.height ?? 0
        let x = Int(floor(rect.origin.x))
        let y = Int(floor(primaryHeight - rect.origin.y - rect.height))
        let width = Int(ceil(rect.width))
        let height = Int(ceil(rect.height))
        return (x, y, max(1, width), max(1, height))
    }
}
