import Foundation
import Testing
@testable import PasteIt

@MainActor
@Suite("Removal toast lifecycle", .serialized)
struct RemovalFeedbackTests {
    private func awaitDismissal(_ feedback: RemovalFeedback) async throws {
        // Other suites share MainActor; allow due tasks to drain without depending on resume order.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while feedback.toast != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(feedback.toast == nil)
    }

    @Test func toastExpiresAfterDisplayDuration() async throws {
        let feedback = RemovalFeedback(displayDuration: .milliseconds(40))
        feedback.show("Synthetic removal", removalID: UUID())
        #expect(feedback.toast != nil)
        try await awaitDismissal(feedback)
    }

    @Test func hoverPausesAndExitResumesDismissal() async throws {
        let feedback = RemovalFeedback(displayDuration: .milliseconds(40))
        feedback.show("Synthetic removal")
        feedback.setHovered(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(feedback.toast != nil)
        feedback.setHovered(false)
        try await awaitDismissal(feedback)
    }

    @Test func replacementIgnoresOldDismissalAndRespectsHover() async throws {
        let feedback = RemovalFeedback(displayDuration: .milliseconds(40))
        feedback.show("First")
        let oldID = try #require(feedback.toast?.id)
        feedback.setHovered(true)
        feedback.show("Second")
        feedback.dismiss(id: oldID)
        try await Task.sleep(for: .milliseconds(100))
        #expect(feedback.toast?.message == "Second")
        feedback.setHovered(false)
        try await awaitDismissal(feedback)
        feedback.show("Third")
        feedback.dismiss()
        #expect(feedback.toast == nil)
    }
}
