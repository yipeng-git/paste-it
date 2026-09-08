import Testing
@testable import PasteItCore

@Suite("Timeline action policy")
struct TimelinePrimaryActionTests {
    @Test func defaultIsUnifiedForEveryInstallAndExplicitChoicesPersist() {
        for saved in [nil, "", "legacy", "unknown"] as [String?] {
            #expect(TimelinePrimaryAction.initialValue(saved: saved) == .paste)
        }
        #expect(TimelinePrimaryAction.initialValue(saved: "copyOnly") == .copyOnly)
        #expect(TimelinePrimaryAction.initialValue(saved: "paste") == .paste)
    }

    @Test func primaryActionHasNoTriggerSpecificException() {
        #expect(TimelinePrimaryAction.allCases == [.paste, .copyOnly])
        #expect(TimelinePrimaryAction.paste.shouldPaste)
        #expect(!TimelinePrimaryAction.copyOnly.shouldPaste)
    }
}
