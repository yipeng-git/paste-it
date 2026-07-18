import Foundation

enum HistoryReadDTO {
    static let htmlTruncateLimit = 8_000
    static let textTruncateLimit = 50_000

    struct Clip: Encodable {
        let id: String
        let createdAt: String
        let updatedAt: String
        let copyCount: Int
        let title: String
        let plainText: String
        let htmlText: String?
        let htmlTruncated: Bool
        let primaryType: String
        let pasteboardTypes: [String]
        let sourceAppName: String?
        let sourceBundleIdentifier: String?
        let ocrText: String?
        let fileURLString: String?
        let linkTitle: String?
        let searchableText: String
        let foldedSearchHaystack: String
        let imagePixelWidth: Int?
        let imagePixelHeight: Int?
        let hasBlob: Bool
        let hasThumbnail: Bool
        let hasLinkImage: Bool
        let hasLinkIcon: Bool
        let blobRelativePath: String?
        let thumbnailRelativePath: String?
        let linkImageRelativePath: String?
        let linkIconRelativePath: String?
        let pinboardIDs: [String]
        let contentHash: String
        let imageBlobBase64: String?
        let thumbnailBlobBase64: String?
    }

    static func encode(
        _ item: ClipItem,
        blobStore: BlobStore? = nil,
        includeBlobs: Bool = false,
        truncateHTML: Bool = true
    ) -> Clip {
        var html = item.htmlText
        var htmlTruncated = false
        if truncateHTML, let raw = html, raw.count > htmlTruncateLimit {
            html = String(raw.prefix(htmlTruncateLimit))
            htmlTruncated = true
        }

        var plain = item.plainText
        if plain.count > textTruncateLimit {
            plain = String(plain.prefix(textTruncateLimit))
        }

        var imageBlobBase64: String?
        var thumbnailBlobBase64: String?
        if includeBlobs, let blobStore {
            if let data = blobStore.data(for: item.blobRelativePath) {
                imageBlobBase64 = data.base64EncodedString()
            }
            if let data = blobStore.data(for: item.thumbnailRelativePath) {
                thumbnailBlobBase64 = data.base64EncodedString()
            }
        }

        return Clip(
            id: item.id.uuidString,
            createdAt: iso8601(item.createdAt),
            updatedAt: iso8601(item.updatedAt),
            copyCount: item.copyCount,
            title: item.title,
            plainText: plain,
            htmlText: html,
            htmlTruncated: htmlTruncated,
            primaryType: item.primaryType.rawValue,
            pasteboardTypes: item.pasteboardTypes,
            sourceAppName: item.sourceAppName,
            sourceBundleIdentifier: item.sourceBundleIdentifier,
            ocrText: item.ocrText,
            fileURLString: item.fileURLString,
            linkTitle: item.linkTitle,
            searchableText: item.searchableText,
            foldedSearchHaystack: item.foldedSearchHaystack,
            imagePixelWidth: item.imagePixelWidth,
            imagePixelHeight: item.imagePixelHeight,
            hasBlob: item.blobRelativePath != nil,
            hasThumbnail: item.thumbnailRelativePath != nil,
            hasLinkImage: item.linkImageRelativePath != nil,
            hasLinkIcon: item.linkIconRelativePath != nil,
            blobRelativePath: item.blobRelativePath,
            thumbnailRelativePath: item.thumbnailRelativePath,
            linkImageRelativePath: item.linkImageRelativePath,
            linkIconRelativePath: item.linkIconRelativePath,
            pinboardIDs: item.pinboardIDs.map(\.uuidString),
            contentHash: item.contentHash,
            imageBlobBase64: imageBlobBase64,
            thumbnailBlobBase64: thumbnailBlobBase64
        )
    }

    private static func iso8601(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateTimeSeparator(.standard).time(includingFractionalSeconds: true))
    }
}
