import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
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
                finish()
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
                    finish()
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

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinished()
    }
}
