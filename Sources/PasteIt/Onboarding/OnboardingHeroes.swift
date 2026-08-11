import SwiftUI

struct OnboardingHeroView: View {
    let page: OnboardingPageID
    let isActive: Bool

    var body: some View {
        Group {
            switch page {
            case .capture: CaptureHero(isActive: isActive)
            case .paste: PasteHero(isActive: isActive)
            case .browse: BrowseHero(isActive: isActive)
            case .organize: OrganizeHero(isActive: isActive)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scene wrapper

private struct HeroScene<Content: View>: View {
    let page: OnboardingPageID
    let beat: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            DemoStepRail(labels: page.stepLabels, current: min(beat, page.stepLabels.count - 1))
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Capture — Copy → saved (menu bar flash + new card)

private struct CaptureHero: View {
    let isActive: Bool

    var body: some View {
        OnboardingBeatLoop(isActive: isActive, delays: [1.2, 2.2]) { beat in
            HeroScene(page: .capture, beat: beat) {
                VStack(spacing: 14) {
                    DemoMenuBarStrip(cPressed: beat == 0, vPressed: false)
                        .demoFocus(beat == 0)

                    HStack(alignment: .center, spacing: 14) {
                        DemoAppWindow(
                            title: "Notes",
                            systemImage: "note.text",
                            emphasized: beat == 0,
                            bodyText: "Ship the onboarding…",
                            placeholder: "…"
                        )
                        .demoFocus(beat == 0)

                        VStack(spacing: 6) {
                            KeyCapsule(label: "⌘ C", pulsing: beat == 0, emphasized: beat == 0)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.tertiary)
                        }

                        ZStack(alignment: .leading) {
                            ScaledDemoCard(clip: .link, scale: 0.40, opacity: 0.35)
                            ScaledDemoCard(
                                clip: .notes,
                                isSelected: beat >= 1,
                                scale: 0.40,
                                opacity: beat >= 1 ? 1 : 0
                            )
                            .offset(x: beat >= 1 ? 44 : 90)
                        }
                        .frame(width: 180, height: OnboardingCardMetrics.fullHeight * 0.40, alignment: .leading)
                        .demoFocus(beat >= 1)
                    }
                }
            }
        }
    }
}

// MARK: - Paste — Open timeline → double-click → ⌘V → ⌃⌘V plain

private struct PasteHero: View {
    let isActive: Bool
    /// Second card in the demo strip (Link).
    private let targetIndex = 1
    private let pasteResult = "Paste It Docs\nexample.com/docs"

    var body: some View {
        OnboardingBeatLoop(isActive: isActive, delays: [1.1, 1.5, 1.7, 2.2]) { beat in
            HeroScene(page: .paste, beat: beat) {
                VStack(spacing: 10) {
                    if beat == 0 {
                        KeyCapsule(label: "⇧ ⌘ V", pulsing: true, emphasized: true)
                    }

                    HStack(alignment: .center, spacing: 14) {
                        OnboardingTimelineChrome {
                            HStack(spacing: 8) {
                                ForEach(Array(OnboardingDemoClip.timelineStrip.prefix(3).enumerated()), id: \.element.id) { index, clip in
                                    ZStack(alignment: .bottomTrailing) {
                                        ScaledDemoCard(
                                            clip: clip,
                                            isSelected: beat >= 1 && index == targetIndex,
                                            scale: 0.38,
                                            opacity: cardOpacity(beat: beat, index: index)
                                        )

                                        if beat == 1 && index == targetIndex {
                                            DemoDoubleClickCue(isActive: true)
                                                .offset(x: 8, y: 10)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                            .padding(.top, 4)
                        }
                        .frame(width: 340, height: 168)
                        .offset(y: beat == 0 ? 10 : 0)
                        .demoFocus(beat <= 1)

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                            .opacity(beat >= 2 ? 1 : 0.25)

                        VStack(spacing: 8) {
                            DemoAppWindow(
                                title: "Pages",
                                emphasized: beat >= 2,
                                bodyText: beat >= 2 ? pasteResult : nil,
                                placeholder: "Empty document"
                            )
                            if beat >= 3 {
                                KeyCapsule(label: "⌃ ⌘ V", pulsing: true, emphasized: true)
                                Text("Paste without formatting")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            } else {
                                KeyCapsule(label: "⌘ V", pulsing: beat == 2, emphasized: beat == 2)
                                    .opacity(beat >= 2 ? 1 : 0.3)
                            }
                        }
                        .demoFocus(beat >= 2)
                    }
                }
            }
        }
    }

    private func cardOpacity(beat: Int, index: Int) -> Double {
        if beat == 0 { return 0.85 }
        return index == targetIndex ? 1 : 0.35
    }
}

// MARK: - Browse — Space → bubble above panel → click text to edit in-place

private struct BrowseHero: View {
    let isActive: Bool

    var body: some View {
        OnboardingBeatLoop(isActive: isActive, delays: [1.0, 1.5, 2.2]) { beat in
            HeroScene(page: .browse, beat: beat) {
                // Keep cue inside the stage (overlay), not as an extra row that
                // collides with the window footer.
                VStack(spacing: 8) {
                    ZStack {
                        Color.clear.frame(height: 96)
                        if beat >= 1 {
                            ProductLikeBubble(isEditing: beat >= 2)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .demoFocus(beat >= 1)

                    ZStack(alignment: .bottom) {
                        OnboardingTimelineChrome {
                            HStack(spacing: 8) {
                                ForEach(Array(OnboardingDemoClip.timelineStrip.prefix(3).enumerated()), id: \.element.id) { index, clip in
                                    ScaledDemoCard(
                                        clip: clip,
                                        isSelected: index == 0,
                                        scale: 0.32,
                                        opacity: index == 0 ? 1 : 0.35
                                    )
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                            .padding(.top, 4)
                        }
                        .frame(width: 460, height: 138)
                        .demoFocus(beat == 0)

                        if beat == 0 {
                            KeyCapsule(label: "Space", pulsing: true, emphasized: true)
                                .padding(.bottom, 10)
                        } else if beat == 2 {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Click text in bubble")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
    }
}

/// Matches real Space bubble: glass panel above timeline; edit = TextEditor in place.
private struct ProductLikeBubble: View {
    var isEditing: Bool
    private let text = "Meeting notes — ship onboarding this week, keep the first-run path short."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                HStack(alignment: .top, spacing: 0) {
                    Text(text)
                        .font(.system(size: 12))
                        .lineLimit(3)
                    BlinkingCaret()
                        .padding(.top, 1)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                }
            } else {
                Text(text)
                    .font(.system(size: 12))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                    .padding(8)
            }
        }
        .padding(8)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
    }
}

private struct BlinkingCaret: View {
    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 0.5, paused: false)) { context in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5, height: 14)
                .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
        }
    }
}

// MARK: - Organize — multi-select → Return pastes in order

private struct OrganizeHero: View {
    let isActive: Bool
    private let lines = ["First address", "Second snippet", "Third line"]

    var body: some View {
        OnboardingBeatLoop(isActive: isActive, delays: [1.4, 1.1, 2.2]) { beat in
            HeroScene(page: .organize, beat: beat) {
                HStack(alignment: .center, spacing: 20) {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach(Array(OnboardingDemoClip.stackItems.enumerated()), id: \.element.id) { index, clip in
                                let selected = selectedCount(beat) > index
                                ScaledDemoCard(
                                    clip: clip,
                                    isSelected: selected,
                                    multiSelectIndex: selected ? index + 1 : nil,
                                    scale: 0.36,
                                    opacity: selected || beat == 0 ? 1 : 0.35
                                )
                            }
                        }
                        if beat <= 1 {
                            KeyCapsule(
                                label: "⌘-click",
                                pulsing: beat == 0,
                                emphasized: beat <= 1
                            )
                        } else {
                            Text("3 selected — Return to paste")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .demoFocus(beat <= 1)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .opacity(beat >= 2 ? 1 : 0.3)

                    VStack(spacing: 8) {
                        DemoAppWindow(
                            title: "Mail",
                            emphasized: beat >= 2,
                            bodyText: beat >= 2 ? lines.joined(separator: "\n") : nil,
                            placeholder: "Compose…"
                        )
                        .frame(width: 168, height: 110)

                        KeyCapsule(label: "Return", pulsing: beat >= 2, emphasized: beat >= 2)
                            .opacity(beat >= 2 ? 1 : 0.3)
                    }
                    .demoFocus(beat >= 2)
                }
            }
        }
    }

    private func selectedCount(_ beat: Int) -> Int {
        switch beat {
        case 0: return 1
        case 1: return 3
        default: return 3
        }
    }
}
