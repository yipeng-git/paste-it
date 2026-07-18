import Foundation

enum OnboardingPageID: Int, CaseIterable, Identifiable {
    case welcome
    case capture
    case timeline
    case stage
    case nextSteps

    var id: Int { rawValue }
}
