import AppKit
import Carbon
import Foundation

/// Watches ⌘C / ⌘V press & release for the menu-bar keycaps.
/// Hold → solid keycap; release (key or ⌘) → hollow again.
/// Uses global + local monitors so it works in other apps and while Paste It is focused.
/// Requires Accessibility for the global monitor (same permission Paste Stack already needs).
@MainActor
final class CmdCVKeyFlashMonitor {
    /// `true` = key chord down, `false` = released.
    private let onCommandC: (Bool) -> Void
    private let onCommandV: (Bool) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cHeld = false
    private var vHeld = false

    init(onCommandC: @escaping (Bool) -> Void, onCommandV: @escaping (Bool) -> Void) {
        self.onCommandC = onCommandC
        self.onCommandV = onCommandV
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        // Drop any held visuals if monitoring stops.
        releaseAll()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            handleKeyDown(event)
        case .keyUp:
            handleKeyUp(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            break
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Exact ⌘C / ⌘V — ignore ⇧⌘C / ⇧⌘V (those are Paste It hotkeys).
        guard isCommandOnly(event.modifierFlags) else { return }
        // Key-repeat would otherwise re-publish the same pressed image every tick.
        guard !event.isARepeat else { return }

        switch Int(event.keyCode) {
        case kVK_ANSI_C:
            guard !cHeld else { return }
            cHeld = true
            onCommandC(true)
        case kVK_ANSI_V:
            guard !vHeld else { return }
            vHeld = true
            onCommandV(true)
        default:
            break
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_ANSI_C:
            guard cHeld else { return }
            cHeld = false
            onCommandC(false)
        case kVK_ANSI_V:
            guard vHeld else { return }
            vHeld = false
            onCommandV(false)
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Releasing ⌘ while C/V is still physically down should clear the solid keycaps.
        guard !event.modifierFlags.contains(.command) else { return }
        releaseAll()
    }

    private func releaseAll() {
        if cHeld {
            cHeld = false
            onCommandC(false)
        }
        if vHeld {
            vHeld = false
            onCommandV(false)
        }
    }

    private func isCommandOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
        let masked = flags.intersection(.deviceIndependentFlagsMask)
        return masked.contains(.command)
            && !masked.contains(.shift)
            && !masked.contains(.option)
            && !masked.contains(.control)
    }
}
