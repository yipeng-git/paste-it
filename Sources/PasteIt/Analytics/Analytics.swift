import Foundation
import PostHog

/// Anonymous product analytics (PostHog). Never send clipboard contents here.
///
/// Event catalog and privacy disclosure: `AnalyticsCatalog` and `docs/analytics.md`.
@MainActor
enum Analytics {
    private static let firstOpenUTCKey = "analyticsFirstOpenUTC"
    private static let installTrackedKey = "analyticsInstallTracked"
    private static var didSetup = false

    /// Active timeline panel session (P0). Reset on `panel_closed`.
    private static var panelSession = PanelSession()

    /// Call once at launch. No-ops when the project token is missing or analytics is disabled.
    static func start(enabled: Bool) {
        guard !didSetup else {
            setEnabled(enabled)
            return
        }

        let token = projectToken()
        guard !token.isEmpty else {
            #if DEBUG
            print("[Analytics] PostHog token missing — set Secrets/posthog.env or POSTHOG_PROJECT_TOKEN, then rebuild the .app")
            #endif
            return
        }

        let config = PostHogConfig(projectToken: token, host: projectHost())
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.optOut = !enabled
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(baseProperties())
        didSetup = true

        guard enabled else { return }
        trackInstallIfNeeded()
        capture("app_open")
    }

    static func stop() {
        guard didSetup, isEnabled else { return }
        if panelSession.isOpen {
            endPanelSession()
        }
        capture("app_exit")
        PostHogSDK.shared.flush()
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "analyticsEnabled")
        guard didSetup else { return }
        if enabled {
            PostHogSDK.shared.optIn()
            capture("app_open")
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    static func capture(_ event: String, properties: [String: Any]? = nil) {
        guard didSetup, isEnabled else { return }
        if let properties {
            PostHogSDK.shared.capture(event, properties: properties)
        } else {
            PostHogSDK.shared.capture(event)
        }
    }

    static func pageView(_ pageName: String, properties: [String: Any]? = nil) {
        var payload = properties ?? [:]
        payload["page_name"] = pageName
        capture("pageview", properties: payload)
    }

    static func click(_ elementName: String, properties: [String: Any]? = nil) {
        var payload = properties ?? [:]
        payload["element_name"] = elementName
        capture("click", properties: payload)
    }

    // MARK: - P0: Onboarding

    static func onboardingStarted(source: String) {
        capture("onboarding_started", properties: ["source": source])
    }

    static func onboardingStepViewed(step: String) {
        capture("onboarding_step_viewed", properties: ["step": step])
    }

    static func onboardingCompleted(outcome: String, lastStep: String) {
        capture(
            "onboarding_completed",
            properties: [
                "outcome": outcome,
                "last_step": lastStep
            ]
        )
    }

    // MARK: - P0: Panel session

    static var isPanelSessionOpen: Bool { panelSession.isOpen }

    static func beginPanelSession(source: String, historyCount: Int) {
        guard !panelSession.isOpen else { return }
        panelSession = PanelSession(
            isOpen: true,
            sessionID: UUID().uuidString,
            source: source,
            openedAt: Date()
        )
        capture(
            "panel_opened",
            properties: [
                "source": source,
                "history_count_bucket": Buckets.historyCount(historyCount),
                "session_id": panelSession.sessionID as Any
            ]
        )
    }

    static func endPanelSession() {
        guard panelSession.isOpen, let openedAt = panelSession.openedAt else {
            panelSession = PanelSession()
            return
        }
        let durationMS = Int(Date().timeIntervalSince(openedAt) * 1000)
        let didStage = panelSession.stages > 0
        let sessionID = panelSession.sessionID
        let stages = panelSession.stages
        let searches = panelSession.searches
        let captures = panelSession.captures

        capture(
            "panel_closed",
            properties: [
                "duration_ms_bucket": Buckets.durationMS(durationMS),
                "did_stage": didStage,
                "session_id": sessionID as Any
            ]
        )
        capture(
            "session_summary",
            properties: [
                "opens": 1,
                "stages": stages,
                "searches": searches,
                "captures_while_open": captures,
                "session_id": sessionID as Any
            ]
        )
        panelSession = PanelSession()
    }

    static func notePanelSearch() {
        guard panelSession.isOpen else { return }
        panelSession.searches += 1
    }

    static func notePanelCapture() {
        guard panelSession.isOpen else { return }
        panelSession.captures += 1
    }

    // MARK: - P0: Capture / stage

    static func clipCaptured(clipType: String, hasOCRScheduled: Bool, isDuplicateSkip: Bool) {
        capture(
            "clip_captured",
            properties: [
                "clip_type": clipType,
                "has_ocr_scheduled": hasOCRScheduled,
                "is_duplicate_skip": isDuplicateSkip
            ]
        )
        if !isDuplicateSkip {
            notePanelCapture()
        }
    }

    static func clipStaged(
        mode: String,
        trigger: String,
        clipType: String,
        tab: String,
        ageBucket: String
    ) {
        if panelSession.isOpen {
            panelSession.stages += 1
        }
        var props: [String: Any] = [
            "mode": mode,
            "trigger": trigger,
            "clip_type": clipType,
            "tab": tab,
            "age_bucket": ageBucket
        ]
        if let sessionID = panelSession.sessionID {
            props["session_id"] = sessionID
        }
        capture("clip_staged", properties: props)
    }

    // MARK: - P0: Updates

    static func updateInteraction(
        action: String,
        source: String,
        fromVersion: String,
        toVersion: String? = nil,
        result: String? = nil
    ) {
        var props: [String: Any] = [
            "action": action,
            "source": source,
            "from_version": fromVersion
        ]
        if let toVersion { props["to_version"] = toVersion }
        if let result { props["result"] = result }
        capture("update_interaction", properties: props)
    }

    // MARK: - Buckets (fixed cardinality)

    enum Buckets {
        static func historyCount(_ count: Int) -> String {
            switch count {
            case 0: return "0"
            case 1...10: return "1-10"
            case 11...50: return "11-50"
            case 51...200: return "51-200"
            default: return "200+"
            }
        }

        static func durationMS(_ ms: Int) -> String {
            switch ms {
            case ..<1_000: return "<1s"
            case ..<3_000: return "1-3s"
            case ..<10_000: return "3-10s"
            case ..<30_000: return "10-30s"
            case ..<60_000: return "30-60s"
            default: return "60s+"
            }
        }

        static func age(since date: Date, now: Date = Date()) -> String {
            let seconds = now.timeIntervalSince(date)
            switch seconds {
            case ..<60: return "<1m"
            case ..<3_600: return "<1h"
            case ..<86_400: return "<1d"
            case ..<604_800: return "<1w"
            default: return "older"
            }
        }
    }

    // MARK: - Private

    private struct PanelSession {
        var isOpen = false
        var sessionID: String?
        var source: String?
        var openedAt: Date?
        var stages = 0
        var searches = 0
        var captures = 0
    }

    private static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: "analyticsEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "analyticsEnabled")
    }

    private static func projectToken() -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "PostHogProjectToken") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func projectHost() -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://us.i.posthog.com" : trimmed
    }

    private static func baseProperties() -> [String: Any] {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let buildVersion = info?["CFBundleVersion"] as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"

        return [
            "app_name": "Paste It",
            "app_version": shortVersion,
            "app_build": buildVersion,
            "platform": "macos",
            "os": "macOS",
            "os_version": osVersion,
            "first_open_utc": firstOpenUTC(),
            "$app_name": "Paste It",
            "$app_version": shortVersion,
            "$os": "macOS",
            "$os_version": "macOS \(os.majorVersion)"
        ]
    }

    private static func firstOpenUTC() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: firstOpenUTCKey), !existing.isEmpty {
            return existing
        }
        let value = ISO8601DateFormatter().string(from: Date())
        defaults.set(value, forKey: firstOpenUTCKey)
        return value
    }

    private static func trackInstallIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: installTrackedKey) else { return }
        capture("app_install", properties: ["install_utc": firstOpenUTC()])
        defaults.set(true, forKey: installTrackedKey)
    }
}
