import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
    let path: String

    static func placeholder(bundleIdentifier: String) -> InstalledApp {
        let icon = NSWorkspace.shared.icon(for: .application)
        icon.size = NSSize(width: 32, height: 32)
        return InstalledApp(
            bundleIdentifier: bundleIdentifier,
            name: bundleIdentifier,
            icon: icon,
            path: ""
        )
    }
}

enum InstalledAppCatalog {
    static func load() -> [InstalledApp] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        var appsByBundle: [String: InstalledApp] = [:]
        let workspace = NSWorkspace.shared

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !bundleID.isEmpty
                else { continue }

                let name = (
                    bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ) ?? (
                    bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ) ?? url.deletingPathExtension().lastPathComponent

                let icon = workspace.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)

                let candidate = InstalledApp(
                    bundleIdentifier: bundleID,
                    name: name,
                    icon: icon,
                    path: url.path
                )

                // Prefer /Applications over System/Applications duplicates.
                if let existing = appsByBundle[bundleID] {
                    let preferCandidate =
                        candidate.path.hasPrefix("/Applications")
                        && !existing.path.hasPrefix("/Applications")
                    if preferCandidate {
                        appsByBundle[bundleID] = candidate
                    }
                } else {
                    appsByBundle[bundleID] = candidate
                }
            }
        }

        // Ensure currently ignored apps still appear even if not found on disk.
        return appsByBundle.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
