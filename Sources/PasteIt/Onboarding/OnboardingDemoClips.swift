import AppKit
import SwiftUI

/// Lightweight stand-in for `ClipItem` so onboarding never touches SwiftData.
struct OnboardingDemoClip: Identifiable {
    let id: UUID
    let type: ClipType
    let previewText: String
    let linkTitle: String?
    let linkHost: String?
    let sourceBundleIdentifier: String?
    let createdAt: Date
    let characterCount: Int?

    init(
        id: UUID = UUID(),
        type: ClipType,
        previewText: String,
        linkTitle: String? = nil,
        linkHost: String? = nil,
        sourceBundleIdentifier: String? = nil,
        createdAt: Date = Date().addingTimeInterval(-120),
        characterCount: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.previewText = previewText
        self.linkTitle = linkTitle
        self.linkHost = linkHost
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.createdAt = createdAt
        self.characterCount = characterCount
    }

    static let notes = OnboardingDemoClip(
        type: .text,
        previewText: "Meeting notes — ship onboarding this week, keep the first-run path short.",
        sourceBundleIdentifier: "com.apple.Notes",
        createdAt: Date().addingTimeInterval(-90),
        characterCount: 72
    )

    static let link = OnboardingDemoClip(
        type: .url,
        previewText: "https://example.com/docs",
        linkTitle: "Paste It Docs",
        linkHost: "example.com/docs",
        sourceBundleIdentifier: "com.apple.Safari",
        createdAt: Date().addingTimeInterval(-40)
    )

    static let code = OnboardingDemoClip(
        type: .text,
        previewText: "func stage(_ item: ClipItem) {\n  pasteboard.clear()\n  pasteboard.write(item)\n}",
        sourceBundleIdentifier: "com.apple.dt.Xcode",
        createdAt: Date().addingTimeInterval(-20),
        characterCount: 84
    )

    static let image = OnboardingDemoClip(
        type: .image,
        previewText: "Screenshot",
        sourceBundleIdentifier: "com.apple.Screenshot",
        createdAt: Date().addingTimeInterval(-8)
    )

    static let favorite = OnboardingDemoClip(
        type: .text,
        previewText: "Thanks for your email — I’ll get back to you by Friday.",
        sourceBundleIdentifier: "com.apple.mail",
        createdAt: Date().addingTimeInterval(-3600),
        characterCount: 54
    )

    static let stackItems: [OnboardingDemoClip] = [
        OnboardingDemoClip(
            type: .text,
            previewText: "First address",
            sourceBundleIdentifier: "com.apple.Safari",
            characterCount: 13
        ),
        OnboardingDemoClip(
            type: .text,
            previewText: "Second snippet",
            sourceBundleIdentifier: "com.apple.Notes",
            characterCount: 14
        ),
        OnboardingDemoClip(
            type: .text,
            previewText: "Third line",
            sourceBundleIdentifier: "com.apple.mail",
            characterCount: 10
        )
    ]

    static let timelineStrip: [OnboardingDemoClip] = [.notes, .link, .code, .image]
}

/// Visual twin of `ClipCardView` (same proportions, banner, ⌘ badge, source icon).
struct OnboardingClipCard: View {
    let clip: OnboardingDemoClip
    var isSelected: Bool = false
    var quickIndex: Int? = nil

    private let cardCornerRadius: CGFloat = 18
    private let headerHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            header
            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            if let footer = footerText {
                Text(footer)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.type.displayTitle)
                    .font(.system(size: 15, weight: .bold))
                Text(clip.createdAt.pasteItCopiedLabel())
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)

            Spacer(minLength: 8)

            if let quickIndex {
                Text("⌘\(quickIndex)")
                    .font(.system(size: 10, weight: .bold).monospaced())
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.22), in: Capsule())
            }

            if let icon = sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: headerHeight)
        .background(clip.type.bannerFallbackColor)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch clip.type {
        case .url:
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color.secondary.opacity(0.08)
                    Image(systemName: "link")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 96)

                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.linkTitle ?? clip.previewText)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if let host = clip.linkHost {
                        Text(host)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case .image:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "E24B4A").opacity(0.18),
                        Color(hex: "2F7DE8").opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "photo")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            Text(clip.previewText)
                .font(.system(size: 14, weight: .regular))
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
        }
    }

    private var footerText: String? {
        switch clip.type {
        case .text, .richText, .html, .mixed, .file:
            guard let count = clip.characterCount else { return nil }
            return count == 1 ? "1 character" : "\(count) characters"
        case .image:
            return "1920 × 1080"
        case .url:
            return nil
        }
    }

    private var sourceIcon: NSImage? {
        guard let bundleID = clip.sourceBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Mini floating-timeline chrome matching `TimelineView` toolbar + glass panel.
struct OnboardingTimelineChrome<Content: View>: View {
    var selectedTab: TimelineTab = .timeline
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Opaque chrome for the onboarding window — do NOT use ClearHostingBackground /
        // pasteItPanelGlass here; those clear the host NSWindow for the floating timeline.
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(TimelineTab.fixedTabs) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if selectedTab == tab {
                                Capsule().fill(Color.primary.opacity(0.12))
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
            }
            .padding(3)
            .pasteItCapsuleGlass()

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search (⌘F)")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 160, height: 30)
            .pasteItControlGlass()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

enum OnboardingCardMetrics {
    /// Real timeline card size from `TimelineView`.
    static let fullWidth: CGFloat = 238
    static let fullHeight: CGFloat = 232
    static let heroScale: CGFloat = 0.55
    static var heroWidth: CGFloat { fullWidth * heroScale }
    static var heroHeight: CGFloat { fullHeight * heroScale }
}
