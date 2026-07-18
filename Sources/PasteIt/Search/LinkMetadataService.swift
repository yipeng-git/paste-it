import AppKit
import Foundation

struct LinkMetadata {
    var title: String?
    var iconData: Data?
    var imageData: Data?
}

actor LinkMetadataService {
    static let shared = LinkMetadataService()

    private var cache: [String: LinkMetadata] = [:]
    private var inFlight: [String: Task<LinkMetadata, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) PasteIt/1.0"
        ]
        return URLSession(configuration: config)
    }()

    func metadata(for url: URL) async -> LinkMetadata {
        let key = Self.cacheKey(for: url)
        if let cached = cache[key] {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<LinkMetadata, Never> {
            await self.fetchMetadata(for: url)
        }
        inFlight[key] = task
        let result = await task.value
        cache[key] = result
        inFlight[key] = nil
        return result
    }

    private func fetchMetadata(for url: URL) async -> LinkMetadata {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return LinkMetadata()
        }

        var metadata = LinkMetadata()
        guard let html = await fetchHTML(from: url) else {
            metadata.iconData = await downloadImage(from: faviconFallbackURL(for: url))
            return metadata
        }

        let baseURL = url
        metadata.title = Self.firstMatch(in: html, patterns: [
            #"property=["']og:title["']\s+content=["']([^"']+)["']"#,
            #"content=["']([^"']+)["']\s+property=["']og:title["']"#,
            #"<title[^>]*>([^<]+)</title>"#
        ]).map(Self.decodeHTMLEntities)

        if let ogImage = Self.firstMatch(in: html, patterns: [
            #"property=["']og:image["']\s+content=["']([^"']+)["']"#,
            #"content=["']([^"']+)["']\s+property=["']og:image["']"#
        ]), let imageURL = URL(string: ogImage, relativeTo: baseURL)?.absoluteURL {
            metadata.imageData = await downloadImage(from: imageURL)
        }

        let iconCandidates = Self.iconHrefs(in: html)
            .compactMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        for candidate in iconCandidates {
            if let data = await downloadImage(from: candidate) {
                metadata.iconData = data
                break
            }
        }
        if metadata.iconData == nil {
            metadata.iconData = await downloadImage(from: faviconFallbackURL(for: url))
        }

        return metadata
    }

    private func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return nil
            }
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8
            }
            return String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }

    private func downloadImage(from url: URL?) async -> Data? {
        guard let url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return nil
            }
            guard !data.isEmpty, NSImage(data: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func faviconFallbackURL(for url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/favicon.ico"
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    private static func cacheKey(for url: URL) -> String {
        url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func firstMatch(in html: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, options: [], range: range),
                  match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: html) else {
                continue
            }
            let value = String(html[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func iconHrefs(in html: String) -> [String] {
        let patterns = [
            #"<link[^>]+rel=["'][^"']*apple-touch-icon[^"']*["'][^>]+href=["']([^"']+)["']"#,
            #"<link[^>]+href=["']([^"']+)["'][^>]+rel=["'][^"']*apple-touch-icon[^"']*["']"#,
            #"<link[^>]+rel=["'][^"']*icon[^"']*["'][^>]+href=["']([^"']+)["']"#,
            #"<link[^>]+href=["']([^"']+)["'][^>]+rel=["'][^"']*icon[^"']*["']"#
        ]
        var hrefs: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                guard let match,
                      match.numberOfRanges > 1,
                      let capture = Range(match.range(at: 1), in: html) else { return }
                let href = String(html[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !href.isEmpty, !hrefs.contains(href) {
                    hrefs.append(href)
                }
            }
        }
        return hrefs
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return string }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return string
    }
}
