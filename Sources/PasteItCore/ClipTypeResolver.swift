import Foundation

/// Pure capture-time type resolution (no AppKit).
///
/// Priority: file URLs (including directories / multi-select) → image pixels →
/// web URL / looks-like-URL text → rich text → HTML → plain text.
public enum ClipTypeResolver {
    public struct Input: Equatable, Sendable {
        public var fileURLs: [URL]
        public var webURL: URL?
        public var plainText: String
        public var hasHTML: Bool
        public var hasRTF: Bool
        public var hasImageData: Bool

        public init(
            fileURLs: [URL] = [],
            webURL: URL? = nil,
            plainText: String = "",
            hasHTML: Bool = false,
            hasRTF: Bool = false,
            hasImageData: Bool = false
        ) {
            self.fileURLs = fileURLs
            self.webURL = webURL
            self.plainText = plainText
            self.hasHTML = hasHTML
            self.hasRTF = hasRTF
            self.hasImageData = hasImageData
        }
    }

    public struct Result: Equatable, Sendable {
        /// Matches `ClipType.rawValue` in the app target.
        public var primaryTypeRaw: String
        public var isDirectory: Bool
        public var fileURLStrings: [String]

        public init(primaryTypeRaw: String, isDirectory: Bool, fileURLStrings: [String]) {
            self.primaryTypeRaw = primaryTypeRaw
            self.isDirectory = isDirectory
            self.fileURLStrings = fileURLStrings
        }
    }

    public static func resolve(_ input: Input) -> Result {
        let fileURLs = dedupe(input.fileURLs)
        let fileURLStrings = fileURLs.map(\.absoluteString)
        let isDirectory = fileURLs.count == 1 && isDirectoryURL(fileURLs[0])

        if !fileURLs.isEmpty {
            return Result(
                primaryTypeRaw: "file",
                isDirectory: isDirectory,
                fileURLStrings: fileURLStrings
            )
        }

        if input.hasImageData {
            return Result(primaryTypeRaw: "image", isDirectory: false, fileURLStrings: [])
        }

        if let web = input.webURL, isWebURL(web) {
            return Result(primaryTypeRaw: "url", isDirectory: false, fileURLStrings: [])
        }

        if looksLikeWebURL(input.plainText) {
            return Result(primaryTypeRaw: "url", isDirectory: false, fileURLStrings: [])
        }

        if input.hasRTF {
            return Result(primaryTypeRaw: "richText", isDirectory: false, fileURLStrings: [])
        }

        if input.hasHTML {
            return Result(primaryTypeRaw: "html", isDirectory: false, fileURLStrings: [])
        }

        return Result(primaryTypeRaw: "text", isDirectory: false, fileURLStrings: [])
    }

    /// http / https / mailto only — never `file://`.
    public static func looksLikeWebURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    public static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    public static func isDirectoryURL(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        var isDir: ObjCBool = false
        if url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }

    private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }
}
