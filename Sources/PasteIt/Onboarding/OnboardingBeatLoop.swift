import SwiftUI

/// Shared beat clock for onboarding heroes. Advances `beat` while `isActive`,
/// resets to 0 and cancels when inactive or delays change.
struct OnboardingBeatLoop<Content: View>: View {
    let isActive: Bool
    /// Dwell time for each beat index before advancing (loops after the last).
    let delays: [TimeInterval]
    @ViewBuilder var content: (_ beat: Int) -> Content

    @State private var beat = 0

    var body: some View {
        content(beat)
            .task(id: taskID) {
                guard isActive, !delays.isEmpty else {
                    beat = 0
                    return
                }
                beat = 0
                var index = 0
                while !Task.isCancelled {
                    let delay = delays[index % delays.count]
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    index += 1
                    withAnimation(.easeInOut(duration: 0.32)) {
                        beat = index % delays.count
                    }
                }
            }
    }

    private var taskID: String {
        "\(isActive)-\(delays.map { String($0) }.joined(separator: ","))"
    }
}
