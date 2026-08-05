import AppKit
import Carbon
import Foundation

/// Watches for ⌘C / ⌘V and flashes the matching menu-bar keycap.
/// Uses global + local monitors so it works in other apps and while Paste It is focused.
/// Requires Accessibility for the global monitor (same permission Paste Stack already needs).
@MainActor
final class CmdCVKeyFlashMonitor {
    private let onCommandC: () -> Void
    private let onCommandV: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(onCommandC: @escaping () -> Void, onCommandV: @escaping () -> Void) {
        self.onCommandC = onCommandC
        self.onCommandV = onCommandV
    }

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
    }

    private func handle(_ event: NSEvent) {
        // Exact ⌘C / ⌘V — ignore ⇧⌘C / ⇧⌘V (those are Paste It hotkeys).
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandOnly = flags.contains(.command)
            && !flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.control)
        guard commandOnly else { return }

        switch Int(event.keyCode) {
        case kVK_ANSI_C:
            onCommandC()
        case kVK_ANSI_V:
            onCommandV()
        default:
            break
        }
    }
}
