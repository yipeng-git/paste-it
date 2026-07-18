import AppKit
import ImageIO
import SwiftUI

/// Caches decoded images, banner colors, pixel sizes.
/// Image dictionary uses NSCache so memory can be reclaimed under pressure.
@MainActor
final class ClipVisualCache {
    static let shared = ClipVisualCache()

    private let imageByPath = NSCache<NSString, NSImage>()
    private let sourceIconByBundle = NSCache<NSString, NSImage>()
    private var pixelSizeByClip: [UUID: (width: Int, height: Int)] = [:]
    private var inflightLoads: [String: Task<NSImage?, Never>] = [:]

    init() {
        imageByPath.countLimit = 120
        imageByPath.totalCostLimit = 48 * 1024 * 1024
        sourceIconByBundle.countLimit = 64
    }

    func cachedImage(at relativePath: String?) -> NSImage? {
        guard let relativePath else { return nil }
        return imageByPath.object(forKey: relativePath as NSString)
    }

    /// Synchronous decode — prefer `loadImage` / `cachedImage` on hot UI paths.
    func image(at relativePath: String?, blobStore: BlobStore) -> NSImage? {
        guard let relativePath else { return nil }
        if let cached = imageByPath.object(forKey: relativePath as NSString) {
            return cached
        }
        guard let url = blobStore.url(for: relativePath),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        imageByPath.setObject(image, forKey: relativePath as NSString, cost: estimatedCost(for: image))
        return image
    }

    func loadImage(at relativePath: String?, blobStore: BlobStore) async -> NSImage? {
        guard let relativePath else { return nil }
        if let cached = imageByPath.object(forKey: relativePath as NSString) {
            return cached
        }
        if let existing = inflightLoads[relativePath] {
            return await existing.value
        }

        let url = blobStore.url(for: relativePath)
        let task = Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let url else { return nil }
            return NSImage(contentsOf: url)
        }
        inflightLoads[relativePath] = task
        let image = await task.value
        inflightLoads[relativePath] = nil
        if let image {
            imageByPath.setObject(image, forKey: relativePath as NSString, cost: estimatedCost(for: image))
        }
        return image
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
        pixelSizeByClip.removeValue(forKey: clipID)
    }

    func invalidatePath(_ relativePath: String?) {
        guard let relativePath else { return }
        imageByPath.removeObject(forKey: relativePath as NSString)
        inflightLoads[relativePath]?.cancel()
        inflightLoads[relativePath] = nil
    }

    func removeAll() {
        imageByPath.removeAllObjects()
        sourceIconByBundle.removeAllObjects()
        pixelSizeByClip.removeAll(keepingCapacity: true)
        for (_, task) in inflightLoads {
            task.cancel()
        }
        inflightLoads.removeAll(keepingCapacity: true)
    }

    private func estimatedCost(for image: NSImage) -> Int {
        let pixels = max(Int(image.size.width * image.size.height), 1)
        return pixels * 4
    }
}
