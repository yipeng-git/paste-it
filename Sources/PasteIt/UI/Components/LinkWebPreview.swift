import AppKit
import SwiftUI
import WebKit

/// Loads a URL in an embedded `WKWebView` for link quick-preview.
struct LinkWebPreview: NSViewRepresentable {
    let urlString: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        loadIfNeeded(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        if context.coordinator.loadedURLString != urlString {
            loadIfNeeded(webView)
            context.coordinator.loadedURLString = urlString
        }
    }

    private func loadIfNeeded(_ webView: WKWebView) {
        guard let url = Self.resolvedURL(from: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    static func resolvedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURLString: String?
        weak var webView: WKWebView?
    }
}
