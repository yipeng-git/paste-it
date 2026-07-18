import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class BlobStore: @unchecked Sendable {
    private let fileManager = FileManager.default
    let rootURL: URL
    let blobsURL: URL
    let thumbnailsURL: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = appSupport.appendingPathComponent("PasteIt", isDirectory: true)
        blobsURL = rootURL.appendingPathComponent("Blobs", isDirectory: true)
        thumbnailsURL = rootURL.appendingPathComponent("Thumbnails", isDirectory: true)
        createDirectories()
    }

    @discardableResult
    func store(data: Data, preferredExtension: String, id: UUID = UUID()) throws -> String {
        createDirectories()
        let fileName = "\(id.uuidString).\(preferredExtension)"
        let url = blobsURL.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return relativePath(for: url)
    }

    /// Stores a thumbnail via ImageIO and returns the relative path plus source pixel size.
    @discardableResult
    func storeThumbnail(
        fromImageData data: Data,
        id: UUID = UUID(),
        maxDimension: CGFloat = 360
    ) throws -> (path: String, pixelWidth: Int, pixelHeight: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let pixelWidth: Int
        let pixelHeight: Int
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            pixelWidth = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            pixelHeight = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        } else {
            pixelWidth = 0
            pixelHeight = 0
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        createDirectories()
        let url = thumbnailsURL.appendingPathComponent("\(id.uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return (relativePath(for: url), pixelWidth, pixelHeight)
    }

    /// Legacy NSImage path kept for callers that only have a decoded image.
    @discardableResult
    func storeThumbnail(for image: NSImage, id: UUID = UUID()) throws -> String? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return try storeThumbnail(fromImageData: tiff, id: id)?.path
    }

    func url(for relativePath: String?) -> URL? {
        guard let relativePath else { return nil }
        return rootURL.appendingPathComponent(relativePath)
    }

    func data(for relativePath: String?) -> Data? {
        guard let url = url(for: relativePath) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Reads pixel dimensions from the image file header without fully decoding.
    func pixelSize(for relativePath: String?) -> (width: Int, height: Int)? {
        guard let url = url(for: relativePath),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        return (width, height)
    }

    func prune(maxMegabytes: Int) {
        let limitBytes = maxMegabytes * 1024 * 1024
        let urls = ((try? fileManager.contentsOfDirectory(
            at: blobsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? [])
        let files = urls.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        let total = files.reduce(0) { $0 + $1.2 }
        guard total > limitBytes else { return }

        var runningTotal = total
        for file in files.sorted(by: { $0.1 < $1.1 }) {
            try? fileManager.removeItem(at: file.0)
            runningTotal -= file.2
            if runningTotal <= limitBytes { break }
        }
    }

    private func relativePath(for url: URL) -> String {
        let root = rootURL.path + "/"
        return url.path.replacingOccurrences(of: root, with: "")
    }

    private func createDirectories() {
        try? fileManager.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
    }
}
