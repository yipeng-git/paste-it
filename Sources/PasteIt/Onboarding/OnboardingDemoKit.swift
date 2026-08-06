import SwiftUI

// MARK: - Shared demo chrome (props only — driven by hero beats)

struct KeyCapsule: View {
    let label: String
    var pulsing: Bool = false
    var emphasized: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold).monospaced())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                (emphasized || pulsing ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08)),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.accentColor.opacity(emphasized || pulsing ? 0.55 : 0), lineWidth: 1.5)
            }
            .scaleEffect(pulsing ? 1.06 : 1)
            .opacity(pulsing || emphasized ? 1 : 0.85)
            .animation(
                pulsing
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
    }
}

struct ScaledDemoCard: View {
    let clip: OnboardingDemoClip
    var isSelected: Bool = false
    var quickIndex: Int? = nil
    var multiSelectIndex: Int? = nil
    var scale: CGFloat = OnboardingCardMetrics.heroScale
    var opacity: Double = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingClipCard(clip: clip, isSelected: isSelected, quickIndex: quickIndex)
                .frame(width: OnboardingCardMetrics.fullWidth, height: OnboardingCardMetrics.fullHeight)
                .scaleEffect(scale)
                .frame(
                    width: OnboardingCardMetrics.fullWidth * scale,
                    height: OnboardingCardMetrics.fullHeight * scale
                )

            if let multiSelectIndex {
                Text("\(multiSelectIndex)")
                    .font(.system(size: 11, weight: .bold).monospaced())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor, in: Circle())
                    .offset(x: 4, y: 4)
            }
        }
        .opacity(opacity)
    }
}

/// SwiftUI stand-in for the menu-bar ⌘C / ⌘V keycaps (not the real AppKit status item).
struct DemoMenuBarKeycaps: View {
    var cPressed: Bool = false
    var vPressed: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            demoKey("C", pressed: cPressed)
            demoKey("V", pressed: vPressed)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func demoKey(_ label: String, pressed: Bool) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold).monospaced())
            .foregroundStyle(pressed ? Color(nsColor: .windowBackgroundColor) : .primary)
            .frame(width: 16, height: 15)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(pressed ? Color.primary : Color.primary.opacity(0.12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
            }
    }
}

struct DemoMenuBarStrip: View {
    var cPressed: Bool = false
    var vPressed: Bool = false

    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Color.secondary.opacity(0.25)).frame(width: 8, height: 8)
                Circle().fill(Color.secondary.opacity(0.25)).frame(width: 8, height: 8)
                DemoMenuBarKeycaps(cPressed: cPressed, vPressed: vPressed)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 8)
    }
}

struct DemoPreviewBubble: View {
    let clip: OnboardingDemoClip
    var editingHint: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(clip.type.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if editingHint {
                    Text("Click to edit")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(clip.previewText)
                .font(.system(size: 13))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

struct DemoTypeFilterChip: View {
    enum Filter: String, CaseIterable {
        case all = "All"
        case text = "Text"
        case link = "Links"
        case image = "Images"
    }

    var selected: Filter = .all

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Filter.allCases, id: \.rawValue) { filter in
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        if selected == filter {
                            Capsule().fill(Color.accentColor.opacity(0.2))
                        }
                    }
                    .foregroundStyle(selected == filter ? Color.accentColor : .secondary)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

struct DemoFolderTabs: View {
    enum Tab: Hashable {
        case timeline
        case pinned
        case folder(String)
    }

    var selected: Tab = .timeline
    var folderName: String = "Work"

    var body: some View {
        HStack(spacing: 2) {
            tabLabel("Default", systemImage: "clock", selected: selected == .timeline)
            tabLabel("Pinned", systemImage: "pin.fill", selected: selected == .pinned)
            tabLabel(folderName, systemImage: "folder", selected: {
                if case .folder = selected { return true }
                return false
            }())
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    private func tabLabel(_ title: String, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if selected {
                Capsule().fill(Color.primary.opacity(0.12))
            }
        }
        .foregroundStyle(selected ? .primary : .secondary)
    }
}

/// In-stage step rail — highlight only the active beat; dim the rest.
struct DemoStepRail: View {
    let labels: [String]
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 5) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold).monospaced())
                        .foregroundStyle(index == current ? Color(nsColor: .windowBackgroundColor) : .secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle().fill(index == current ? Color.accentColor : Color.secondary.opacity(0.2))
                        )
                    Text(label)
                        .font(.system(size: 11, weight: index == current ? .semibold : .medium))
                        .foregroundStyle(index == current ? .primary : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    if index == current {
                        Capsule().fill(Color.accentColor.opacity(0.12))
                    }
                }
                .opacity(index <= current ? 1 : 0.45)

                if index < labels.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }
}

/// Tiny faux app window used as source / destination in causal scenes.
struct DemoAppWindow: View {
    let title: String
    var systemImage: String = "macwindow"
    var emphasized: Bool = false
    var bodyText: String? = nil
    var placeholder: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(Color.red.opacity(0.55)).frame(width: 7, height: 7)
                Circle().fill(Color.yellow.opacity(0.55)).frame(width: 7, height: 7)
                Circle().fill(Color.green.opacity(0.55)).frame(width: 7, height: 7)
                Spacer(minLength: 4)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color.secondary.opacity(0.12))

            ZStack(alignment: .topLeading) {
                Color(nsColor: .textBackgroundColor)
                if let bodyText, !bodyText.isEmpty {
                    Text(bodyText)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .padding(8)
                } else if !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(8)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 148, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    emphasized ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1),
                    lineWidth: emphasized ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(emphasized ? 0.12 : 0.04), radius: emphasized ? 8 : 3, y: 2)
    }
}

/// Dim inactive scene panels so only one beat owns attention.
struct DemoFocus: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0.32)
            .saturation(active ? 1 : 0.6)
    }
}

extension View {
    func demoFocus(_ active: Bool) -> some View {
        modifier(DemoFocus(active: active))
    }
}

/// Two quick press pulses to read as a double-click on a card.
struct DemoDoubleClickCue: View {
    var isActive: Bool

    @State private var press = false
    @State private var token = 0

    var body: some View {
        ZStack {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .scaleEffect(press ? 0.82 : 1)
                .opacity(isActive ? 1 : 0)

            Text("Double-click")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
                .offset(y: 22)
                .opacity(isActive ? 1 : 0)
        }
        .onChange(of: isActive) { _, active in
            token += 1
            if active {
                runPulse(token: token)
            } else {
                press = false
            }
        }
        .onAppear {
            if isActive { runPulse(token: token) }
        }
    }

    private func runPulse(token: Int) {
        Task { @MainActor in
            while token == self.token, isActive {
                withAnimation(.easeIn(duration: 0.08)) { press = true }
                try? await Task.sleep(for: .milliseconds(90))
                guard token == self.token else { return }
                withAnimation(.easeOut(duration: 0.1)) { press = false }
                try? await Task.sleep(for: .milliseconds(100))
                guard token == self.token else { return }
                withAnimation(.easeIn(duration: 0.08)) { press = true }
                try? await Task.sleep(for: .milliseconds(90))
                guard token == self.token else { return }
                withAnimation(.easeOut(duration: 0.1)) { press = false }
                try? await Task.sleep(for: .milliseconds(900))
            }
        }
    }
}
