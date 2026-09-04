import SwiftUI

/// Shared between the onboarding window and SwiftUI view so close-without-button still reports.
@MainActor
final class OnboardingAnalyticsHandle {
    let source: String
    private(set) var lastStep: String = OnboardingPageID.capture.analyticsName
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
    var flow: OnboardingFlow
    var analytics: OnboardingAnalyticsHandle
    var onFinished: () -> Void

    @State private var pageIndex = 0
    @State private var navigateForward = true

    private var pages: [OnboardingPageID] { OnboardingPageID.pages(for: flow) }
    private var isLastPage: Bool { pageIndex >= pages.count - 1 }
    private var currentPage: OnboardingPageID { pages[pageIndex] }

    private let footerHeight: CGFloat = 44
    private let titleBlockHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            titleBlock
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .frame(height: titleBlockHeight, alignment: .top)
                .clipped()
                .layoutPriority(1)

            heroSection
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(0)

            footer
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .layoutPriority(1)
        }
        .frame(width: 640, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            analytics.markStarted()
            analytics.markStep(currentPage.analyticsName)
        }
        .onChange(of: pageIndex) { _, _ in
            analytics.markStep(currentPage.analyticsName)
        }
        .localizedRefreshTrigger()
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(currentPage.title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
            Text(currentPage.caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
        }
        .id(currentPage)
    }

    private var heroSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            OnboardingHeroView(page: currentPage, isActive: true)
                .id(currentPage)
                .transition(pageTransition)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.28), value: pageIndex)
    }

    private var footer: some View {
        // Equal-width leading/trailing columns keep dots centered and stop
        // Back/Continue from shifting when Skip is narrow or Back is hidden.
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Button("Skip") {
                    finish(outcome: "skipped")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            pageIndicators

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("Back") {
                    go(to: pageIndex - 1, forward: false)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(pageIndex > 0 ? 1 : 0)
                .disabled(pageIndex == 0)
                .allowsHitTesting(pageIndex > 0)

                Button(isLastPage ? finishButtonTitle : "Continue") {
                    if isLastPage {
                        finish(outcome: "completed")
                    } else {
                        go(to: pageIndex + 1, forward: true)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .frame(width: 110)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: footerHeight)
    }

    private var finishButtonTitle: String {
        flow == .update ? "Done" : "Get Started"
    }

    private var pageIndicators: some View {
        HStack(spacing: 6) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(index == pageIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle().size(width: 16, height: 16))
                    .onTapGesture {
                        go(to: index, forward: index >= pageIndex)
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
        stampCompletion()
        onFinished()
    }

    private func stampCompletion() {
        switch flow {
        case .install:
            settings.hasCompletedOnboarding = true
            settings.seenWhatsNewContentVersion = AppSettings.currentWhatsNewContentVersion
        case .update:
            settings.seenWhatsNewContentVersion = AppSettings.currentWhatsNewContentVersion
        }
    }
}
