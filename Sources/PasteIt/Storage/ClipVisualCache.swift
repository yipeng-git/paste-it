import AppKit
import ImageIO
import SwiftUI
import PasteItCore

/// Caches decoded images, banner colors, pixel sizes.
/// Image dictionary uses NSCache so memory can be reclaimed under pressure.
@MainActor
final class ClipVisualCache {
    static let shared = ClipVisualCache()

    private let imageByPath = NSCache<NSString, NSImage>()
    private let sourceIconByBundle = NSCache<NSString, NSImage>()
    private var pixelSizeByClip: [UUID: (width: Int, height: Int)] = [:]
    private var inflightLoads: [String: Task<CGImage?, Never>] = [:]
    private var loadTokens: [String: UUID] = [:]
    private final class TextEntry {
        let revision: Date
        let summary: ClipPreviewText.Summary
        init(item: ClipItem) {
            revision = item.updatedAt
            summary = ClipPreviewText.Summary(item.previewText)
        }
    }
    private let textByClip = NSCache<NSUUID, TextEntry>()

    init() {
        imageByPath.countLimit = 120
        imageByPath.totalCostLimit = 48 * 1024 * 1024
        sourceIconByBundle.countLimit = 64
        textByClip.countLimit = 240
    }

    func cardText(for item: ClipItem) -> ClipPreviewText.Summary {
        let key = item.id as NSUUID
        if let entry = textByClip.object(forKey: key), entry.revision == item.updatedAt {
            return entry.summary
        }
        let entry = TextEntry(item: item)
        textByClip.setObject(entry, forKey: key)
        return entry.summary
    }

    private func imageKey(_ path: String, blobStore: BlobStore, maxPixelSize: Int) -> String {
        "\(blobStore.rootURL.path)|\(path)|\(maxPixelSize)"
    }

    func cachedImage(at relativePath: String?, blobStore: BlobStore, maxPixelSize: Int = 720) -> NSImage? {
        guard let relativePath else { return nil }
        return imageByPath.object(forKey: imageKey(relativePath, blobStore: blobStore, maxPixelSize: maxPixelSize) as NSString)
    }

    /// Legacy full-image access for non-card callers. UI preview uses async downsampling.
    func image(at relativePath: String?, blobStore: BlobStore) -> NSImage? {
        guard let relativePath else { return nil }
        let key = imageKey(relativePath, blobStore: blobStore, maxPixelSize: 0) as NSString
        if let cached = imageByPath.object(forKey: key) { return cached }
        guard let url = blobStore.url(for: relativePath), let image = NSImage(contentsOf: url) else { return nil }
        imageByPath.setObject(image, forKey: key, cost: estimatedCost(for: image))
        return image
    }

    func loadImage(at relativePath: String?, blobStore: BlobStore, maxPixelSize: Int = 720) async -> NSImage? {
        guard let relativePath, let url = blobStore.url(for: relativePath) else { return nil }
        let key = imageKey(relativePath, blobStore: blobStore, maxPixelSize: maxPixelSize)
        if let cached = imageByPath.object(forKey: key as NSString) { return cached }
        if let existing = inflightLoads[key] {
            guard let bitmap = await existing.value, !Task.isCancelled else { return nil }
            return NSImage(cgImage: bitmap, size: .zero)
        }
        let token = UUID()
        let task = Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard !Task.isCancelled else { return nil }
            return ImageDownsampler.image(at: url, maxPixelSize: maxPixelSize)
        }
        inflightLoads[key] = task
        loadTokens[key] = token
        let bitmap = await task.value
        // Invalidation must not allow an older load to refill the cache.
        guard loadTokens[key] == token else { return nil }
        inflightLoads[key] = nil
        loadTokens[key] = nil
        guard let bitmap else { return nil }
        let image = NSImage(cgImage: bitmap, size: .zero)
        imageByPath.setObject(image, forKey: key as NSString, cost: bitmap.bytesPerRow * bitmap.height)
        return Task.isCancelled ? nil : image
    }

    /// Resolve source app icon by bundle ID (no per-clip PNG in the store).
    func sourceIcon(for item: ClipItem) -> NSImage? {
        guard let bundleID = item.sourceBundleIdentifier, !bundleID.isEmpty else {
            return nil
        }
        let key = bundleID as NSString
        if let cached = sourceIconByBundle.object(forKey: key) {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 64, height: 64)
        sourceIconByBundle.setObject(icon, forKey: key, cost: estimatedCost(for: icon))
        return icon
    }

    /// Banner color is type-based (Link / Image / Text), not sampled from the app icon.
    func bannerColor(for item: ClipItem) -> Color {
        item.primaryType.bannerFallbackColor
    }

    func pixelSize(for item: ClipItem, blobStore: BlobStore) -> (width: Int, height: Int)? {
        if let cached = pixelSizeByClip[item.id] {
            return cached
        }
        if let stored = item.storedImagePixelSize {
            pixelSizeByClip[item.id] = stored
            return stored
        }
        let size = blobStore.pixelSize(for: item.blobRelativePath)
            ?? blobStore.pixelSize(for: item.thumbnailRelativePath)
        if let size {
            pixelSizeByClip[item.id] = size
        }
        return size
    }

    func invalidate(clipID: UUID) {
        textByClip.removeObject(forKey: clipID as NSUUID)
        pixelSizeByClip.removeValue(forKey: clipID)
    }

    func invalidatePath(_ relativePath: String?, blobStore: BlobStore) {
        guard let relativePath else { return }
        // These are the three supported decode sizes: original, card and preview.
        for size in [0, 720, 1_600] {
            imageByPath.removeObject(forKey: imageKey(relativePath, blobStore: blobStore, maxPixelSize: size) as NSString)
        }
        for key in Array(inflightLoads.keys) where key.contains("|\(relativePath)|") {
            inflightLoads.removeValue(forKey: key)?.cancel()
            loadTokens[key] = nil
        }
    }

    func removeAll() {
        textByClip.removeAllObjects()
        imageByPath.removeAllObjects()
        sourceIconByBundle.removeAllObjects()
        pixelSizeByClip.removeAll(keepingCapacity: true)
        for (_, task) in inflightLoads {
            task.cancel()
        }
        inflightLoads.removeAll(keepingCapacity: true)
        loadTokens.removeAll(keepingCapacity: true)
    }

    private func estimatedCost(for image: NSImage) -> Int {
        image.representations.reduce(0) { total, representation in
            if let bitmap = representation as? NSBitmapImageRep {
                return total + bitmap.bytesPerRow * bitmap.pixelsHigh
            }
            return total + max(representation.pixelsWide * representation.pixelsHigh, 1) * 4
        }
    }
}
