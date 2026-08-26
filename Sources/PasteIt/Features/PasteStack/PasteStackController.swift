import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
final class PasteStackController: ObservableObject {
    enum Direction: String, CaseIterable, Identifiable {
        case oldestFirst
        case newestFirst

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oldestFirst: return "First in, first out"
            case .newestFirst: return "Last in, first out"
            }
        }

        var systemImage: String {
            switch self {
            case .oldestFirst: return "arrow.up"
            case .newestFirst: return "arrow.down"
            }
        }

        var toggleHelp: String {
            switch self {
            case .oldestFirst: return "Copy order. Click to reverse."
            case .newestFirst: return "Newest first. Click for copy order."
            }
        }
    }

    @Published private(set) var isCollecting = false
    @Published private(set) var items: [ClipItem] = []
    @Published var direction: Direction = .oldestFirst {
        didSet {
            guard direction != oldValue else { return }
            settings.pasteStackDefaultDirection = direction
        }
    }

    var onChange: (() -> Void)?
    /// Called when the stack panel should appear / refresh / dismiss.
    var onPanelSync: ((Bool) -> Void)?

    private let pasteController: PasteController
    private let settings: AppSettings

    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    /// Let the synthetic ⌘V we post reach the target app instead of re-entering the tap.
    nonisolated(unsafe) private var isPassingSyntheticCommandV = false
    private var didPromptForAccessibility = false
    /// Nested suspends so multi-select sequential paste can post ⌘V without
    /// the Stack intercept swallowing / re-staging mid-sequence.
    private var pasteInterceptSuspendCount = 0
    private var pendingDeliveries = 0
    private var isDrainingDeliveries = false

    init(pasteController: PasteController, settings: AppSettings) {
        self.pasteController = pasteController
        self.settings = settings
        self.direction = settings.pasteStackDefaultDirection
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    /// ⇧⌘C — open Stack (start collecting) or close it (clear queue, like Paste).
    func toggle() {
        if isCollecting || !items.isEmpty {
            close()
        } else {
            open()
        }
    }

    func open() {
        direction = settings.pasteStackDefaultDirection
        items = []
        isCollecting = true
        ensureAccessibilityIfNeeded()
        refreshPasteIntercept()
        notifyChange()
        onPanelSync?(true)
        Analytics.beginPasteStackSession(direction: analyticsDirection)
        NSLog("PasteIt: Paste Stack opened")
    }

    func close() {
        Analytics.endPasteStackSession()
        isCollecting = false
        items = []
        pendingDeliveries = 0
        tearDownEventTap()
        notifyChange()
        onPanelSync?(false)
        NSLog("PasteIt: Paste Stack closed")
    }

    /// Compatibility alias used by menus / settings toggle.
    func toggleCollecting() {
        toggle()
    }

    func startCollecting() { open() }
    func stopCollecting() { close() }

    func append(_ capturedClip: CapturedClip) {
        guard isCollecting else { return }
        let item = capturedClip.makeModel()
        // Only skip a consecutive double-copy. The same value can appear twice
        // in a stack (two form fields, repeated snippets).
        if items.last?.duplicateContentKey == item.duplicateContentKey { return }
        items.append(item)
        refreshPasteIntercept()
        notifyChange()
        onPanelSync?(true)
        Analytics.notePasteStackCollected(count: items.count)
        NSLog("PasteIt: Paste Stack +1 → \(items.count) — \(item.title)")
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        refreshPasteIntercept()
        notifyChange()
        onPanelSync?(isCollecting || !items.isEmpty)
    }

    /// Move `item` to the next-to-paste position for the current direction.
    func promoteToNext(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        switch direction {
        case .oldestFirst:
            items.insert(item, at: 0)
        case .newestFirst:
            items.append(item)
        }
        refreshPasteIntercept()
        notifyChange()
        onPanelSync?(true)
    }

    func clear() {
        items = []
        refreshPasteIntercept()
        notifyChange()
        onPanelSync?(isCollecting)
    }

    /// Stage next item onto the pasteboard only (⌘V intercept re-posts after this).
    @discardableResult
    func stageNext() -> Bool {
        guard !items.isEmpty else { return false }
        let item = removeNext()
        let mode: PasteController.PasteMode = settings.pasteAsPlainTextByDefault ? .plainText : .normal
        let ok = pasteController.copyToPasteboard(item, mode: mode)
        finishStage(itemTitle: item.title)
        return ok
    }

    /// Async stage that reads image blobs off the main thread before writing.
    @discardableResult
    func stageNextAsync() async -> Bool {
        guard !items.isEmpty else { return false }
        let item = removeNext()
        let mode: PasteController.PasteMode = settings.pasteAsPlainTextByDefault ? .plainText : .normal
        let ok: Bool
        if item.primaryType == .image, mode == .normal {
            ok = await pasteController.copyToPasteboardAsync(item, mode: mode)
        } else {
            ok = pasteController.copyToPasteboard(item, mode: mode)
        }
        finishStage(itemTitle: item.title)
        return ok
    }

    private func finishStage(itemTitle: String) {
        refreshPasteIntercept()
        notifyChange()
        if !isCollecting && items.isEmpty {
            onPanelSync?(false)
        }
        NSLog("PasteIt: Paste Stack staged — \(itemTitle) (\(items.count) left)")
    }

    @discardableResult
    func prepareNextForSystemPaste() -> Bool {
        stageNext()
    }

    func flipDirection() {
        direction = direction == .oldestFirst ? .newestFirst : .oldestFirst
        onPanelSync?(isCollecting || !items.isEmpty)
    }

    var statusTitle: String {
        if isCollecting || !items.isEmpty {
            return items.isEmpty ? "Stack" : "Stack · \(items.count)"
        }
        return "Paste"
    }

    var toggleMenuTitle: String {
        if isCollecting || !items.isEmpty {
            return "Close Paste Stack"
        }
        return "Open Paste Stack"
    }

    func ensureAccessibilityIfNeeded() {
        SystemPasteSynthesizer.ensureAccessibilityIfNeeded(didPrompt: &didPromptForAccessibility)
    }

    /// Temporarily disable ⌘V intercept (e.g. while multi-select pastes its own sequence).
    func suspendPasteIntercept() {
        pasteInterceptSuspendCount += 1
        if pasteInterceptSuspendCount == 1 {
            tearDownEventTap()
        }
    }

    func resumePasteIntercept() {
        guard pasteInterceptSuspendCount > 0 else { return }
        pasteInterceptSuspendCount -= 1
        if pasteInterceptSuspendCount == 0 {
            refreshPasteIntercept()
        }
    }

    // MARK: - ⌘V intercept (Paste-compatible)

    private func refreshPasteIntercept() {
        if pasteInterceptSuspendCount > 0 || items.isEmpty {
            tearDownEventTap()
        } else {
            installEventTapIfPossible()
        }
    }

    private func installEventTapIfPossible() {
        if eventTap != nil || pasteInterceptSuspendCount > 0 { return }
        guard AXIsProcessTrusted() else {
            ensureAccessibilityIfNeeded()
            return
        }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<PasteStackController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleEventTap(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            NSLog("PasteIt: failed to create Paste Stack event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("PasteIt: Paste Stack ⌘V intercept enabled")
    }

    private func tearDownEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    nonisolated private func handleEventTap(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard flags.contains(.maskCommand),
              !flags.contains(.maskShift),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskControl),
              keyCode == CGKeyCode(kVK_ANSI_V) else {
            return Unmanaged.passUnretained(event)
        }

        // Synthetic ⌘V we posted must reach the frontmost app.
        if isPassingSyntheticCommandV {
            return Unmanaged.passUnretained(event)
        }

        // Swallow the user's keyUp so it doesn't paste the *previous* clipboard
        // after we already ate the keyDown.
        if type == .keyUp {
            return nil
        }

        // Swallow ⌘V, enqueue a serialized stage → settle → paste.
        // Never block the event-tap thread with main.sync.
        // Rapid ⌘V is queued so we don't skip / double-paste under race.
        Task { @MainActor in
            await self.enqueueDelivery()
        }
        return nil
    }

    @MainActor
    private func enqueueDelivery() async {
        pendingDeliveries += 1
        guard !isDrainingDeliveries else { return }
        isDrainingDeliveries = true
        defer { isDrainingDeliveries = false }

        while pendingDeliveries > 0 {
            pendingDeliveries -= 1
            guard !items.isEmpty else {
                pendingDeliveries = 0
                break
            }
            guard await stageNextAsync() else {
                Analytics.notePasteStackPasteNext(success: false, failReason: "stage_failed")
                continue
            }
            Analytics.notePasteStackPasteNext(success: true, failReason: nil)
            try? await Task.sleep(nanoseconds: SystemPasteSynthesizer.writeSettleNanoseconds)
            // Only the synthetic keystrokes we post should pass the tap.
            isPassingSyntheticCommandV = true
            await SystemPasteSynthesizer.postCommandVAsync()
            isPassingSyntheticCommandV = false
            try? await Task.sleep(nanoseconds: SystemPasteSynthesizer.targetPasteNanoseconds)
        }
    }

    private func removeNext() -> ClipItem {
        let index = direction == .oldestFirst ? 0 : items.count - 1
        return items.remove(at: index)
    }

    private func notifyChange() {
        onChange?()
    }

    private var analyticsDirection: String {
        switch direction {
        case .oldestFirst: return "fifo"
        case .newestFirst: return "lifo"
        }
    }
}
