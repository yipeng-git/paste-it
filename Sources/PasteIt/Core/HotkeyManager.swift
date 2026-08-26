import AppKit
import Carbon
import Foundation

/// Registers system-wide hotkeys via Carbon, which is more reliable than
/// `NSEvent.addGlobalMonitorForEvents` for menu-bar apps (especially unsigned
/// debug builds launched from Terminal / Xcode).
@MainActor
final class HotkeyManager {
    private let showTimeline: () -> Void
    private let togglePasteStack: () -> Void
    private let pastePlain: () -> Bool
    private let editSelected: () -> Bool

    private var eventHandler: EventHandlerRef?
    private var hotKeyShow: EventHotKeyRef?
    private var hotKeyStack: EventHotKeyRef?
    private var hotKeyPastePlain: EventHotKeyRef?

    private var localMonitor: Any?

    private enum HotKeyID: UInt32 {
        case showTimeline = 1
        case togglePasteStack = 2
        case pastePlain = 3
    }

    init(
        showTimeline: @escaping () -> Void,
        togglePasteStack: @escaping () -> Void,
        pastePlain: @escaping () -> Bool,
        editSelected: @escaping () -> Bool
    ) {
        self.showTimeline = showTimeline
        self.togglePasteStack = togglePasteStack
        self.pastePlain = pastePlain
        self.editSelected = editSelected
    }

    func start() {
        stop()
        installCarbonHotKeys()
        installLocalMonitor()
    }

    func stop() {
        if let hotKeyShow { UnregisterEventHotKey(hotKeyShow) }
        if let hotKeyStack { UnregisterEventHotKey(hotKeyStack) }
        if let hotKeyPastePlain { UnregisterEventHotKey(hotKeyPastePlain) }
        hotKeyShow = nil
        hotKeyStack = nil
        hotKeyPastePlain = nil

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    private func installCarbonHotKeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleCarbonEvent(event)
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        guard status == noErr else {
            NSLog("PasteIt: failed to install hotkey handler (\(status))")
            return
        }

        // ⇧⌘V — show timeline
        hotKeyShow = registerHotKey(
            id: .showTimeline,
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        // ⇧⌘C — toggle Paste Stack collecting
        hotKeyStack = registerHotKey(
            id: .togglePasteStack,
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        // ⌃⌘V — paste current clipboard without formatting
        hotKeyPastePlain = registerHotKey(
            id: .pastePlain,
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | controlKey)
        )
    }

    private func registerHotKey(id: HotKeyID, keyCode: UInt32, modifiers: UInt32) -> EventHotKeyRef? {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("pasc"), id: id.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("PasteIt: failed to register hotkey \(id.rawValue) (\(status))")
            return nil
        }
        return hotKeyRef
    }

    nonisolated private func handleCarbonEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            switch HotKeyID(rawValue: hotKeyID.id) {
            case .showTimeline:
                self.showTimeline()
            case .togglePasteStack:
                self.togglePasteStack()
            case .pastePlain:
                _ = self.pastePlain()
            case nil:
                break
            }
        }
        return noErr
    }

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleLocal(event) {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleLocal(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }

        // ⌃⌘V — paste without formatting while Paste It is key.
        if flags.contains(.control),
           !flags.contains(.shift),
           !flags.contains(.option),
           event.keyCode == UInt16(kVK_ANSI_V) {
            return pastePlain()
        }

        // ⌘E opens the editor for the currently selected clip while the panel is key.
        if !flags.contains(.shift),
           !flags.contains(.option),
           !flags.contains(.control),
           event.keyCode == UInt16(kVK_ANSI_E) {
            return editSelected()
        }

        guard flags.contains(.shift), !flags.contains(.option), !flags.contains(.control) else {
            return false
        }

        switch Int(event.keyCode) {
        case kVK_ANSI_V:
            showTimeline()
            return true
        case kVK_ANSI_C:
            togglePasteStack()
            return true
        default:
            return false
        }
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
