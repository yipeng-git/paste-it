import SwiftUI

/// Shared between the onboarding window and SwiftUI view so close-without-button still reports.
@MainActor
final class OnboardingAnalyticsHandle {
    let source: String
    private(set) var lastStep: String = OnboardingPageID.welcome.analyticsName
    private(set) var didComplete = false
    private var didStart = false

    init(source: String) {
        self.source = source
    }

    func markStarted() {
        guard !didStart else { return }
        didStart = true
        Analytics.onboardingStarted(source: source)
    }

    func markStep(_ step: String) {
        lastStep = step
        Analytics.onboardingStepViewed(step: step)
    }

    func markFinished(outcome: String) {
        guard !didComplete else { return }
        didComplete = true
        Analytics.onboardingCompleted(outcome: outcome, lastStep: lastStep)
    }

    func markDismissedIfNeeded() {
        markFinished(outcome: "dismissed")
    }
}

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var analytics: OnboardingAnalyticsHandle
    var onFinished: () -> Void

    @State private var pageIndex = 0
    @State private var navigateForward = true

    private var pages: [OnboardingPageID] { OnboardingPageID.allCases }
    private var isLastPage: Bool { pageIndex >= pages.count - 1 }
    private var currentPage: OnboardingPageID { pages[pageIndex] }

    private let footerHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            heroSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 20)
                .frame(height: footerHeight)
                .padding(.bottom, 14)
                .padding(.top, 10)
        }
        .frame(width: 640, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            analytics.markStarted()
            analytics.markStep(currentPage.analyticsName)
        }
        .onChange(of: pageIndex) { _, _ in
            analytics.markStep(currentPage.analyticsName)
        }
    }

    private var heroSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            OnboardingHeroView(page: currentPage, isActive: true)
                .id(currentPage)
                .transition(pageTransition)
                .padding(16)
                // Hero pages vary in intrinsic size; always fill the slot so the
                // footer never jumps when switching illustrations.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.28), value: pageIndex)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Skip") {
                finish(outcome: "skipped")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            pageIndicators

            Spacer()

            // Reserve Back's width on page 1 so Continue doesn't shift horizontally.
            Button("Back") {
                go(to: pageIndex - 1, forward: false)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .opacity(pageIndex > 0 ? 1 : 0)
            .disabled(pageIndex == 0)
            .allowsHitTesting(pageIndex > 0)

            Button(isLastPage ? "Get Started" : "Continue") {
                if isLastPage {
                    finish(outcome: "completed")
                } else {
                    go(to: pageIndex + 1, forward: true)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .frame(minWidth: 110)
        }
    }

    private var pageIndicators: some View {
        HStack(spacing: 6) {
            ForEach(pages) { page in
                Circle()
                    .fill(page.rawValue == pageIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle().size(width: 16, height: 16))
                    .onTapGesture {
                        go(to: page.rawValue, forward: page.rawValue >= pageIndex)
                    }
            }
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: navigateForward ? .trailing : .leading)),
            removal: .opacity.combined(with: .move(edge: navigateForward ? .leading : .trailing))
        )
    }

    private func go(to index: Int, forward: Bool) {
        guard pages.indices.contains(index), index != pageIndex else { return }
        navigateForward = forward
        withAnimation(.easeInOut(duration: 0.28)) {
            pageIndex = index
        }
    }

    private func finish(outcome: String) {
        analytics.markStep(currentPage.analyticsName)
        analytics.markFinished(outcome: outcome)
        settings.hasCompletedOnboarding = true
        onFinished()
    }
}

extension OnboardingPageID {
    var analyticsName: String {
        switch self {
        case .welcome: return "welcome"
        case .capture: return "capture"
        case .timeline: return "timeline"
        case .stage: return "stage"
        case .nextSteps: return "nextSteps"
        }
    }
}
