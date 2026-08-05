import Foundation

/// Canonical list of analytics events for in-app disclosure and docs.
/// Keep in sync with `docs/analytics.md`.
enum AnalyticsCatalog {
    struct Event: Identifiable {
        let name: String
        let summary: String
        var id: String { name }
    }

    /// Properties attached to every event via PostHog `register`.
    static let commonProperties: [(name: String, summary: String)] = [
        ("app_name / $app_name", "Always \"Paste It\""),
        ("app_version / $app_version", "CFBundleShortVersionString"),
        ("app_build", "CFBundleVersion"),
        ("platform", "\"macos\""),
        ("os / $os", "\"macOS\""),
        ("os_version / $os_version", "OS version (custom field is full; $os_version is major)"),
        ("first_open_utc", "First analytics-enabled open time (ISO8601)")
    ]

    static let lifecycleEvents: [Event] = [
        Event(name: "app_install", summary: "First time analytics is enabled on this Mac"),
        Event(name: "app_open", summary: "App launch or analytics re-enabled"),
        Event(name: "app_exit", summary: "Clean app quit")
    ]

    static let productEvents: [Event] = [
        Event(name: "onboarding_started", summary: "Tutorial opened (first launch or Settings)"),
        Event(name: "onboarding_step_viewed", summary: "Tutorial page shown (step id only)"),
        Event(name: "onboarding_completed", summary: "Tutorial finished, skipped, or dismissed"),
        Event(name: "panel_opened", summary: "Timeline panel shown (hotkey / menu / status item)"),
        Event(name: "panel_closed", summary: "Timeline panel hidden (duration bucket, did stage?)"),
        Event(name: "session_summary", summary: "Per panel session counts (stages / searches) plus search zero-result flag"),
        Event(name: "clip_staged", summary: "Item copied to system pasteboard from timeline"),
        Event(name: "paste_stack_session", summary: "Paste Stack open→close summary (collect / paste-next / Accessibility)"),
        Event(name: "update_interaction", summary: "Sparkle update check / find / download / install / fail")
    ]

    static let neverCollected: [String] = [
        "Clipboard text, HTML, RTF, or previews",
        "OCR text from images",
        "Image / file bytes or local paths",
        "Full search query strings",
        "Clip titles (often derived from content)",
        "Source app clipboard payloads",
        "MCP tool payloads"
    ]

    static let documentationPath = "docs/analytics.md"
    static let documentationURL = URL(string: "https://github.com/yipeng-git/paste-it/blob/main/docs/analytics.md")
}
