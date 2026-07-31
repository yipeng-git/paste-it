import AppKit
import ApplicationServices
import Carbon
import Foundation

/// Synthesizes system ⌘V for sequential paste into the frontmost app.
enum SystemPasteSynthesizer {
    /// Pause after writing the pasteboard so the new changeCount is visible.
    static let writeSettleNanoseconds: UInt64 = 80_000_000
    /// Pause after ⌘V so the target app can read the pasteboard before we overwrite it.
    /// Too short → previous ⌘V pastes the *next* item (skip one, duplicate the next).
    static let targetPasteNanoseconds: UInt64 = 300_000_000
    /// Gap between keyDown and keyUp for a more realistic ⌘V.
    static let keyUpDelayNanoseconds: UInt64 = 12_000_000

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts once per process lifetime when Accessibility is missing.
    static func ensureAccessibilityIfNeeded(didPrompt: inout Bool) {
        guard !AXIsProcessTrusted() else { return }
        guard !didPrompt else { return }
        didPrompt = true
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        NSLog("PasteIt: requesting Accessibility for synthesized ⌘V")
    }

    static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// ⌘V with a short keyDown→keyUp gap (closer to a real keystroke).
    @MainActor
    static func postCommandVAsync() async {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: keyUpDelayNanoseconds)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Write → settle → ⌘V → wait for the frontmost app to consume the pasteboard.
    @MainActor
    static func pasteWrittenItem() async {
        try? await Task.sleep(nanoseconds: writeSettleNanoseconds)
        await postCommandVAsync()
        try? await Task.sleep(nanoseconds: targetPasteNanoseconds)
    }
}
