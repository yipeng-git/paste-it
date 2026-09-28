/// Coordinates the handoff from a background download to the install prompt.
/// Sparkle may present critical updates itself before reporting cycle completion.
public struct AutomaticUpdatePromptState: Sendable {
    private var awaitingPresentation = false

    public init() {}

    public mutating func updatePrepared() {
        awaitingPresentation = true
    }

    public mutating func updatePresented() {
        awaitingPresentation = false
    }

    public mutating func finishCycle(failed: Bool) -> Bool {
        let shouldPresent = awaitingPresentation && !failed
        awaitingPresentation = false
        return shouldPresent
    }
}
