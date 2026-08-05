import Foundation
import SwiftData
import PasteItCore

@Model
final class ClipItem: Identifiable {
    @Attribute(.unique) var id: UUID
    /// Original capture time (Paste `createdAt`). Shown on cards; used for retention.
    var createdAt: Date
    var updatedAt: Date
    /// Sort key for timeline order (Paste `timestamp`). Bumped on reuse / copy / paste.
    var lastUsedAt: Date = Date()
    var title: String
    var plainText: String
    var htmlText: String?
    var rtfData: Data?
    var primaryTypeRaw: String
    var pasteboardTypesRaw: String
    var sourceAppName: String?
    var sourceBundleIdentifier: String?
    var sourceIconPNG: Data?
    var blobRelativePath: String?
    var thumbnailRelativePath: String?
    var fileURLString: String?
    var ocrText: String?
    var linkTitle: String?
    var linkIconRelativePath: String?
    var linkImageRelativePath: String?
    /// Stored at capture time so the timeline never has to open the image file for dimensions.
    var imagePixelWidth: Int?
    var imagePixelHeight: Int?
    var pinboardIDsRaw: String
    var contentHash: String
    var copyCount: Int
    /// Soft-removed from Default; still visible in Pinned / custom folders.
    var isHiddenFromTimeline: Bool = false

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        plainText: String = "",
        htmlText: String? = nil,
        rtfData: Data? = nil,
        primaryType: ClipType,
        pasteboardTypes: [String],
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        sourceIconPNG: Data? = nil,
        blobRelativePath: String? = nil,
        thumbnailRelativePath: String? = nil,
        fileURLString: String? = nil,
        ocrText: String? = nil,
        linkTitle: String? = nil,
        linkIconRelativePath: String? = nil,
        linkImageRelativePath: String? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        pinboardIDs: [UUID] = [],
        contentHash: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastUsedAt = createdAt
        self.title = title
        self.plainText = plainText
        self.htmlText = htmlText
        self.rtfData = rtfData
        self.primaryTypeRaw = primaryType.rawValue
        self.pasteboardTypesRaw = pasteboardTypes.joined(separator: "\n")
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceIconPNG = sourceIconPNG
        self.blobRelativePath = blobRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.fileURLString = fileURLString
        self.ocrText = ocrText
        self.linkTitle = linkTitle
        self.linkIconRelativePath = linkIconRelativePath
        self.linkImageRelativePath = linkImageRelativePath
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.pinboardIDsRaw = pinboardIDs.map(\.uuidString).joined(separator: "\n")
        self.contentHash = contentHash
        self.copyCount = 1
        self.isHiddenFromTimeline = false
    }

    var primaryType: ClipType {
        get { ClipType(rawValue: primaryTypeRaw) ?? .mixed }
        set { primaryTypeRaw = newValue.rawValue }
    }

    var pasteboardTypes: [String] {
        pasteboardTypesRaw
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    var pinboardIDs: [UUID] {
        get {
            pinboardIDsRaw
                .split(whereSeparator: \.isNewline)
                .compactMap { UUID(uuidString: String($0)) }
        }
        set {
            pinboardIDsRaw = newValue.map(\.uuidString).joined(separator: "\n")
            updatedAt = Date()
        }
    }

    var previewText: String {
        let hasRich = htmlText != nil || rtfData != nil
        let richPlain: String? = hasRich
            ? RichPlainText.extract(htmlText: htmlText, rtfData: rtfData)
            : nil
        return ClipPreviewText.resolve(
            plainText: plainText,
            richPlainText: richPlain,
            hasRichPayload: hasRich,
            ocrText: ocrText,
            fileURLString: fileURLString,
            typeTitle: primaryType.title
        )
    }

    /// Fields used for full-text search. Intentionally excludes `htmlText` —
    /// HTML markup dominates haystack size and `plainText` already covers content.
    var searchableText: String {
        [
            title,
            plainText,
            ocrText ?? "",
            sourceAppName ?? "",
            fileURLString ?? "",
            linkTitle ?? "",
            primaryType.title
        ]
        .joined(separator: " ")
    }

    var foldedSearchHaystack: String {
        searchableText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    var storedImagePixelSize: (width: Int, height: Int)? {
        guard let width = imagePixelWidth, let height = imagePixelHeight,
              width > 0, height > 0 else {
            return nil
        }
        return (width, height)
    }

    /// External re-copy of the same content (Paste checksum hit).
    func touchDuplicate() {
        copyCount += 1
        let now = Date()
        updatedAt = now
        lastUsedAt = now
        isHiddenFromTimeline = false
        // Keep createdAt — Paste preserves original capture time.
    }

    /// Copy/paste from history (Paste Cmd-C / Return / Quick Paste).
    func touchAccess() {
        let now = Date()
        updatedAt = now
        lastUsedAt = now
    }
}
