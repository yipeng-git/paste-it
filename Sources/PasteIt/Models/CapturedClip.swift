import AppKit
import Foundation

struct CapturedClip: Sendable {
    let title: String
    let plainText: String
    let htmlText: String?
    let rtfData: Data?
    let primaryType: ClipType
    let pasteboardTypes: [String]
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
    let blobRelativePath: String?
    let thumbnailRelativePath: String?
    let fileURLString: String?
    let ocrText: String?
    let linkTitle: String?
    let linkIconRelativePath: String?
    let linkImageRelativePath: String?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let contentHash: String
    /// When set, OCR runs after insert using this on-disk blob (not kept in RAM).
    let pendingOCRBlobRelativePath: String?

    func makeModel() -> ClipItem {
        ClipItem(
            title: title,
            plainText: plainText,
            htmlText: htmlText,
            rtfData: rtfData,
            primaryType: primaryType,
            pasteboardTypes: pasteboardTypes,
            sourceAppName: sourceAppName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceIconPNG: nil,
            blobRelativePath: blobRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            fileURLString: fileURLString,
            ocrText: ocrText,
            linkTitle: linkTitle,
            linkIconRelativePath: linkIconRelativePath,
            linkImageRelativePath: linkImageRelativePath,
            imagePixelWidth: imagePixelWidth,
            imagePixelHeight: imagePixelHeight,
            contentHash: contentHash
        )
    }
}
