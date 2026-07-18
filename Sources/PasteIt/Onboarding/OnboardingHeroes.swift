import SwiftUI

struct OnboardingHeroView: View {
    let page: OnboardingPageID
    let isActive: Bool

    var body: some View {
        Group {
            switch page {
            case .welcome: WelcomeHero(isActive: isActive)
            case .capture: CaptureHero(isActive: isActive)
            case .timeline: TimelineHero(isActive: isActive)
            case .stage: StageHero(isActive: isActive)
            case .nextSteps: NextStepsHero(isActive: isActive)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(isActive ? 1 : 0.96)
        .opacity(isActive ? 1 : 0.5)
        .animation(.easeOut(duration: 0.28), value: isActive)
    }
}

// MARK: - Shared

private struct KeyCapsule: View {
    let label: String
    var pulsing: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold).monospaced())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
            .scaleEffect(pulsing ? 1.06 : 1)
            .opacity(pulsing ? 1 : 0.85)
            .animation(
                pulsing
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
    }
}

private struct ScaledDemoCard: View {
    let clip: OnboardingDemoClip
    var isSelected: Bool = false
    var quickIndex: Int? = nil
    var scale: CGFloat = OnboardingCardMetrics.heroScale

    var body: some View {
        OnboardingClipCard(clip: clip, isSelected: isSelected, quickIndex: quickIndex)
            .frame(width: OnboardingCardMetrics.fullWidth, height: OnboardingCardMetrics.fullHeight)
            .scaleEffect(scale)
            .frame(width: OnboardingCardMetrics.fullWidth * scale, height: OnboardingCardMetrics.fullHeight * scale)
    }
}

// MARK: - Page 1

private struct WelcomeHero: View {
    let isActive: Bool
    @State private var showLock = false

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                // Mac-ish bezel behind a fan of real cards
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.06))
                    )
                    .frame(width: 280, height: 190)

                HStack(spacing: -40) {
                    ScaledDemoCard(clip: .notes, scale: 0.52)
                        .rotationEffect(.degrees(-10))
                    ScaledDemoCard(clip: .link, isSelected: true, scale: 0.52)
                        .zIndex(1)
                    ScaledDemoCard(clip: .image, scale: 0.52)
                        .rotationEffect(.degrees(10))
                }
            }

            VStack(spacing: 10) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce, value: isActive && showLock)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Stays on this Mac")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .opacity(showLock ? 1 : 0)
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                showLock = false
                withAnimation(.easeOut(duration: 0.45).delay(0.2)) {
                    showLock = true
                }
            }
        }
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeOut(duration: 0.45).delay(0.2)) {
                showLock = true
            }
        }
    }
}

// MARK: - Page 2

private struct CaptureHero: View {
    let isActive: Bool
    @State private var phase = 0
    @State private var animationToken = 0

    var body: some View {
        VStack(spacing: 10) {
            // Menu bar strip with Paste It glyph
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(Color.secondary.opacity(0.25)).frame(width: 8, height: 8)
                    Circle().fill(Color.secondary.opacity(0.25)).frame(width: 8, height: 8)
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                        .background(
                            Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 8)

            HStack(alignment: .center, spacing: 12) {
                Text("Copied!")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(phase == 0 ? 1 : 0.4)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)

                ZStack(alignment: .leading) {
                    ScaledDemoCard(clip: .notes, scale: 0.50)
                        .offset(x: 0)
                        .opacity(0.45)
                    ScaledDemoCard(clip: .link, scale: 0.50)
                        .offset(x: 36)
                        .opacity(0.7)
                    ScaledDemoCard(clip: .code, isSelected: phase >= 1, scale: 0.50)
                        .offset(x: phase >= 1 ? 72 : 120)
                        .opacity(phase >= 1 ? 1 : 0)
                }
                .frame(width: 220, height: OnboardingCardMetrics.fullHeight * 0.50, alignment: .leading)
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                startLoop()
            } else {
                animationToken += 1
                phase = 0
            }
        }
        .onAppear {
            if isActive { startLoop() }
        }
    }

    private func startLoop() {
        animationToken += 1
        let token = animationToken
        phase = 0
        Task { @MainActor in
            while token == animationToken {
                try? await Task.sleep(for: .milliseconds(700))
                guard token == animationToken else { return }
                withAnimation(.easeInOut(duration: 0.35)) { phase = 1 }
                try? await Task.sleep(for: .milliseconds(1600))
                guard token == animationToken else { return }
                withAnimation(.easeInOut(duration: 0.25)) { phase = 0 }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

// MARK: - Page 3

private struct TimelineHero: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            OnboardingTimelineChrome {
                HStack(spacing: 10) {
                    ForEach(Array(OnboardingDemoClip.timelineStrip.enumerated()), id: \.element.id) { index, clip in
                        ScaledDemoCard(
                            clip: clip,
                            isSelected: index == 1,
                            quickIndex: index < 9 ? index + 1 : nil,
                            scale: 0.50
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 6)
            }
            .frame(width: 580, height: 250)

            KeyCapsule(label: "⇧ ⌘ V", pulsing: pulse)
        }
        .onChange(of: isActive) { _, active in
            pulse = active
        }
        .onAppear {
            pulse = isActive
        }
    }
}

// MARK: - Page 4

private struct StageHero: View {
    let isActive: Bool
    @State private var step = 0
    @State private var animationToken = 0

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Step 1")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ScaledDemoCard(clip: .notes, isSelected: step >= 0, quickIndex: 1, scale: 0.50)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    VStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(step >= 1 ? Color.accentColor : .secondary)
                        Text("Clipboard")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(step >= 1 ? 0.12 : 0.04))
                    )
                }
                Text("writes clipboard")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 6) {
                Text("Step 2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 120, height: 72)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                                Text("Other App")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    KeyCapsule(label: "⌘ V", pulsing: step >= 2)
                }
                Text("you press ⌘V")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .opacity(step >= 2 ? 1 : 0.45)
        }
        .onChange(of: isActive) { _, active in
            if active {
                startSequence()
            } else {
                animationToken += 1
                step = 0
            }
        }
        .onAppear {
            if isActive { startSequence() }
        }
    }

    private func startSequence() {
        animationToken += 1
        let token = animationToken
        step = 0
        Task { @MainActor in
            while token == animationToken {
                withAnimation(.easeInOut(duration: 0.25)) { step = 0 }
                try? await Task.sleep(for: .milliseconds(400))
                guard token == animationToken else { return }
                withAnimation(.easeInOut(duration: 0.3)) { step = 1 }
                try? await Task.sleep(for: .milliseconds(900))
                guard token == animationToken else { return }
                withAnimation(.easeInOut(duration: 0.3)) { step = 2 }
                try? await Task.sleep(for: .milliseconds(1600))
            }
        }
    }
}

// MARK: - Page 5

private struct NextStepsHero: View {
    let isActive: Bool
    @State private var pinned = false

    var body: some View {
        HStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Pinboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topTrailing) {
                    ScaledDemoCard(clip: .favorite, isSelected: pinned, scale: 0.55)
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .offset(x: 4, y: -4)
                        .opacity(pinned ? 1 : 0)
                        .scaleEffect(pinned ? 1 : 0.5)
                }
            }

            VStack(spacing: 8) {
                Text("Paste Stack")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(OnboardingDemoClip.stackItems.enumerated()), id: \.element.id) { index, clip in
                        HStack(spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 11, weight: .bold).monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            ScaledDemoCard(clip: clip, scale: 0.42)
                        }
                    }
                }

                Text("paste in order")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                pinned = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15)) {
                    pinned = true
                }
            }
        }
        .onAppear {
            guard isActive else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15)) {
                pinned = true
            }
        }
    }
}
