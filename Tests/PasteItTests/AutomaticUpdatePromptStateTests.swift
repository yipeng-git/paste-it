import Testing
@testable import PasteItCore

@Suite("Automatic update presentation")
struct AutomaticUpdatePromptStateTests {
    @Test func backgroundPreparationPromptsOnceAfterItsCycleFinishes() {
        var state = AutomaticUpdatePromptState()
        state.updatePrepared()
        let shouldPresent = state.finishCycle(failed: false)
        #expect(shouldPresent)
        // Dismissing the ensuing UI must not immediately present it again.
        let shouldPresentAgain = state.finishCycle(failed: false)
        #expect(!shouldPresentAgain)
    }

    @Test func criticalUpdatePresentedBySparkleDoesNotPromptAgainOnDismissal() {
        var state = AutomaticUpdatePromptState()
        state.updatePrepared()
        state.updatePresented()
        let shouldPresentAgain = state.finishCycle(failed: false)
        #expect(!shouldPresentAgain)
    }

    @Test func failureDiscardsPendingPresentationButAllowsALaterUpdate() {
        var state = AutomaticUpdatePromptState()
        state.updatePrepared()
        let shouldPresentAfterFailure = state.finishCycle(failed: true)
        let shouldPresentStaleUpdate = state.finishCycle(failed: false)
        #expect(!shouldPresentAfterFailure)
        #expect(!shouldPresentStaleUpdate)
        state.updatePrepared()
        let shouldPresentNewUpdate = state.finishCycle(failed: false)
        #expect(shouldPresentNewUpdate)
    }

    @Test func checksWithoutAPreparedDownloadNeverOpenAnInstallPrompt() {
        var state = AutomaticUpdatePromptState()
        let shouldPresentAfterSuccess = state.finishCycle(failed: false)
        let shouldPresentAfterFailure = state.finishCycle(failed: true)
        #expect(!shouldPresentAfterSuccess)
        #expect(!shouldPresentAfterFailure)
    }
}
