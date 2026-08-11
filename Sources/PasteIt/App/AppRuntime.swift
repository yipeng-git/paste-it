import AppKit
import SwiftData

@MainActor
final class AppRuntime: NSObject {
    static let shared = AppRuntime()

    let settings: AppSettings
    let blobStore: BlobStore
    let historyStore: HistoryStore
    let searchService: SearchService
    let appState: AppState
    let pasteController: PasteController
    let pasteStackController: PasteStackController
    let pasteboardMonitor: PasteboardMonitor
    let hotkeyManager: HotkeyManager
    let panelController: TimelinePanelController
    let detachedWindowController: ClipDetachedWindowController
    let pasteStackPanelController: PasteStackPanelController

    var state: AppState { appState }

    private var statusItem: NSStatusItem?
    private var keycapsIcon: MenuBarKeycapsIcon?
    private var cmdCVFlashMonitor: CmdCVKeyFlashMonitor?
    private var didStart = false

    private override init() {
        settings = AppSettings()
        blobStore = BlobStore()
        historyStore = HistoryStore(blobStore: blobStore, settings: settings)
        searchService = SearchService()
        appState = AppState(
            settings: settings,
            historyStore: historyStore,
            searchService: searchService
        )
        pasteController = PasteController(blobStore: blobStore)
        pasteStackController = PasteStackController(
            pasteController: pasteController,
            settings: settings
        )
        pasteboardMonitor = PasteboardMonitor(
            settings: settings,
            blobStore: blobStore,
            historyStore: historyStore,
            pasteStackController: pasteStackController
        )
        pasteController.onPasteboardMutation = { [pasteboardMonitor] changeCount in
            pasteboardMonitor.suppress(changeCount: changeCount)
        }
        panelController = TimelinePanelController(appState: appState, pasteController: pasteController)
        detachedWindowController = ClipDetachedWindowController(appState: appState)
        pasteStackPanelController = PasteStackPanelController(
            stack: pasteStackController,
            historyStore: historyStore
        )
        hotkeyManager = HotkeyManager(
            showTimeline: { [panelController] in panelController.toggle(source: .hotkey) },
            togglePasteStack: { [pasteStackController, appState] in
                pasteStackController.toggle()
                if pasteStackController.isCollecting {
                    appState.setStatus("Paste Stack open — copy, then ⌘V to paste in order")
                } else {
                    appState.setStatus("Paste Stack closed")
                }
            },
            pasteStackNext: { [pasteStackController, panelController] in
                guard !pasteStackController.items.isEmpty else { return false }
                pasteStackController.ensureAccessibilityIfNeeded()
                return pasteStackController.pasteNext(panelController: panelController)
            },
            pastePlain: { [pasteController, pasteStackController, panelController, appState] in
                AppRuntime.performPasteWithoutFormatting(
                    pasteController: pasteController,
                    pasteStackController: pasteStackController,
                    panelController: panelController,
                    appState: appState
                )
            },
            editSelected: { [appState, panelController] in
                guard panelController.isVisible else { return false }
                return appState.beginEditingSelectedClip()
            }
        )
        appState.pasteStackController = pasteStackController
        appState.panelController = panelController
        panelController.detachedWindowController = detachedWindowController
        detachedWindowController.timelinePanelController = panelController
        panelController.pasteStackPanelController = pasteStackPanelController
        super.init()

        pasteStackController.onChange = { [weak self] in
            self?.refreshStatusItem()
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        historyStore.load()
        pasteboardMonitor.start()
        hotkeyManager.start()
        detachedWindowController.start()
        configureStatusItem()
        startCmdCVFlashMonitor()
        LaunchAtLoginManager.syncAtStartup(enabled: settings.launchAtLogin)
        // Retain Sparkle updater for automatic background checks.
        _ = UpdateChecker.shared
        Analytics.start(enabled: settings.analyticsEnabled)

        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [settings] in
                guard !settings.hasCompletedOnboarding else { return }
                OnboardingWindowController.shared.show(
                    settings: settings,
                    flow: .install,
                    source: "first_launch"
                )
            }
        } else if settings.seenWhatsNewContentVersion < AppSettings.currentWhatsNewContentVersion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [settings] in
                guard settings.hasCompletedOnboarding else { return }
                guard settings.seenWhatsNewContentVersion < AppSettings.currentWhatsNewContentVersion else { return }
                OnboardingWindowController.shared.show(
                    settings: settings,
                    flow: .update,
                    source: "update"
                )
            }
        }

        applyAgentAPIEnabled(settings.agentAPIEnabled)
    }

    func stop() {
        Analytics.stop()
        AgentAPIServer.shared.stop()
        pasteboardMonitor.stop()
        hotkeyManager.stop()
        cmdCVFlashMonitor?.stop()
        cmdCVFlashMonitor = nil
        pasteStackController.close()
    }

    func applyAgentAPIEnabled(_ enabled: Bool) {
        if enabled {
            // Force rebind so a dead listener after a stuck render can come back.
            AgentAPIServer.shared.start(forceRestart: true)
        } else {
            AgentAPIServer.shared.stop()
        }
    }

    private func configureStatusItem() {
        let size = MenuBarKeycapsIcon.preferredSize
        let item = NSStatusBar.system.statusItem(withLength: size.width)
        guard let button = item.button else {
            statusItem = item
            return
        }

        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Paste It"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.menu = nil

        // Drop any legacy keycaps subview from older builds / reconfigure.
        button.subviews.forEach { $0.removeFromSuperview() }

        let keycaps = MenuBarKeycapsIcon()
        keycaps.onImageChange = { [weak button] image in
            button?.image = image
        }
        keycaps.publish()
        keycapsIcon = keycaps

        statusItem = item
        refreshStatusItem()
    }

    private func startCmdCVFlashMonitor() {
        let monitor = CmdCVKeyFlashMonitor(
            onCommandC: { [weak self] pressed in self?.keycapsIcon?.setPressed(pressed, for: .c) },
            onCommandV: { [weak self] pressed in self?.keycapsIcon?.setPressed(pressed, for: .v) }
        )
        monitor.start()
        cmdCVFlashMonitor = monitor
    }

    private func refreshStatusItem() {
        let stack = pasteStackController.statusTitle
        let stackLine = stack == "Paste" ? nil : stack
        var tip = "Paste It — hold ⌘C / ⌘V to press the keys"
        if let stackLine {
            tip += "\n\(stackLine)"
        }
        tip += "\nLeft-click: timeline · Right-click: menu"
        statusItem?.button?.toolTip = tip
    }

    /// Shared app menu used by the timeline's "…" button.
    func makeAppMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "Open Paste", action: #selector(openTimeline), keyEquivalent: "v", shiftCommand: true))
        menu.addItem(makeMenuItem(
            title: pasteStackController.toggleMenuTitle,
            action: #selector(togglePasteStack),
            keyEquivalent: "c",
            shiftCommand: true
        ))
        if !pasteStackController.items.isEmpty {
            menu.addItem(makeMenuItem(
                title: "Paste Next from Stack",
                action: #selector(pasteNextFromStack),
                keyEquivalent: ""
            ))
            menu.addItem(makeMenuItem(
                title: "Clear Paste Stack",
                action: #selector(clearPasteStack),
                keyEquivalent: ""
            ))
        }
        menu.addItem(makeMenuItem(
            title: "Paste Without Formatting",
            action: #selector(pasteWithoutFormattingMenu),
            keyEquivalent: "v",
            controlCommand: true
        ))
        menu.addItem(NSMenuItem.separator())
        let pauseTitle = settings.capturePaused ? "Resume Capture" : "Pause Capture"
        menu.addItem(makeMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "t", shiftCommand: true))
        let agentItem = makeMenuItem(title: "MCP", action: #selector(toggleAgentAPI), keyEquivalent: "")
        agentItem.state = settings.agentAPIEnabled ? .on : .off
        menu.addItem(agentItem)
        if settings.agentAPIEnabled {
            menu.addItem(makeMenuItem(title: "Copy MCP URL", action: #selector(copyAgentAPIURL), keyEquivalent: ""))
        }
        menu.addItem(makeMenuItem(title: "Preferences…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(makeMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "Quit Paste It", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    /// Pops the app menu below `view` (used by the timeline toolbar "…" button).
    func popUpAppMenu(relativeTo view: NSView) {
        let menu = makeAppMenu()
        let point = NSPoint(x: 0, y: view.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    // MARK: - Actions (also used by the SwiftUI toolbar Menu)

    func openTimelineAction() { openTimeline() }
    func togglePasteStackAction() { togglePasteStack() }
    func togglePauseCaptureAction() { togglePause() }
    func openSettingsAction() { openSettings() }
    func quitAction() { quit() }
    func pasteNextFromStackAction() { pasteNextFromStack() }
    func clearPasteStackAction() { clearPasteStack() }

    var isCapturePaused: Bool { settings.capturePaused }
    var pasteStackToggleTitle: String { pasteStackController.toggleMenuTitle }
    var pasteStackItemCount: Int { pasteStackController.items.count }
    var isPasteStackCollecting: Bool { pasteStackController.isCollecting }

    private func makeMenuItem(
        title: String,
        action: Selector?,
        keyEquivalent: String,
        shiftCommand: Bool = false,
        controlCommand: Bool = false,
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = action == nil ? nil : self
        item.isEnabled = enabled
        if controlCommand, !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = [.command, .control]
        } else if shiftCommand, !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = [.command, .shift]
        }
        return item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            panelController.toggle(source: .statusItem)
        }
    }

    /// Attach the menu to the status item and click it so macOS shows a normal
    /// status-bar menu (no popover caret from `popUp`).
    private func showStatusMenu() {
        guard let item = statusItem else { return }
        item.menu = makeAppMenu()
        item.button?.performClick(nil)
        // performClick blocks while the menu is open; clear afterward so the
        // next left-click opens Timeline instead of this menu.
        item.menu = nil
    }

    @objc private func toggleTimeline() {
        panelController.toggle(source: .hotkey)
    }

    @objc private func openTimeline() {
        panelController.show(source: .menu)
    }

    @objc private func togglePasteStack() {
        pasteStackController.toggle()
        refreshStatusItem()
        if pasteStackController.isCollecting {
            appState.setStatus("Paste Stack open — copy, then ⌘V to paste in order")
        } else {
            appState.setStatus("Paste Stack closed")
        }
    }

    @objc private func pasteNextFromStack() {
        pasteStackController.ensureAccessibilityIfNeeded()
        _ = pasteStackController.pasteNext(panelController: panelController)
    }

    @objc private func pasteWithoutFormattingMenu() {
        _ = pasteWithoutFormatting()
    }

    @objc private func clearPasteStack() {
        pasteStackController.close()
        refreshStatusItem()
    }

    /// ⌃⌘V — strip the current clipboard to plain text and synthesize ⌘V.
    @discardableResult
    func pasteWithoutFormatting() -> Bool {
        Self.performPasteWithoutFormatting(
            pasteController: pasteController,
            pasteStackController: pasteStackController,
            panelController: panelController,
            appState: appState
        )
    }

    @discardableResult
    private static func performPasteWithoutFormatting(
        pasteController: PasteController,
        pasteStackController: PasteStackController,
        panelController: TimelinePanelController,
        appState: AppState
    ) -> Bool {
        pasteStackController.ensureAccessibilityIfNeeded()

        guard let plain = pasteController.plainTextFromGeneralPasteboard() else {
            Analytics.plainPaste(success: false, failReason: "empty")
            appState.setStatus("Nothing to paste as plain text")
            return false
        }

        // Keep the original rich clipboard so a later ⌘V is unchanged.
        let snapshot = pasteController.snapshotGeneralPasteboard()
        guard pasteController.writePlainTextToGeneralPasteboard(plain, markTransient: true) else {
            Analytics.plainPaste(success: false, failReason: "empty")
            appState.setStatus("Nothing to paste as plain text")
            return false
        }

        let accessibilityTrusted = SystemPasteSynthesizer.isAccessibilityTrusted
        pasteStackController.suspendPasteIntercept()
        Task { @MainActor in
            defer { pasteStackController.resumePasteIntercept() }

            // Wait until the panel has dismissed so the previous app is key.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if panelController.isVisible {
                    panelController.hide {
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)

            if accessibilityTrusted {
                // 80ms settle → ⌘V → 300ms for the target app to read plain text.
                await SystemPasteSynthesizer.pasteWrittenItem()
                if let snapshot {
                    _ = pasteController.restoreGeneralPasteboard(snapshot)
                }
                Analytics.plainPaste(success: true, failReason: nil)
                appState.setStatus("Pasted as plain text")
            } else {
                // Can't auto-paste; leave plain so a manual ⌘V still works.
                Analytics.plainPaste(success: false, failReason: "accessibility")
                appState.setStatus("Plain text ready — grant Accessibility to auto-paste, or press ⌘V")
            }
        }
        return true
    }

    @objc private func togglePause() {
        settings.capturePaused.toggle()
    }

    @objc private func toggleAgentAPI() {
        settings.agentAPIEnabled.toggle()
        applyAgentAPIEnabled(settings.agentAPIEnabled)
        if settings.agentAPIEnabled {
            copyAgentAPIURLToPasteboard()
            appState.setStatus("MCP on — URL copied")
        } else {
            appState.setStatus("MCP off")
        }
    }

    @objc private func copyAgentAPIURL() {
        copyAgentAPIURLToPasteboard()
        appState.setStatus("Copied MCP URL — \(AgentAPIServer.defaultBaseURL)")
    }

    private func copyAgentAPIURLToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AgentAPIServer.defaultBaseURL, forType: .string)
        // Don't capture our own "copy URL" into clipboard history.
        pasteboardMonitor.suppress(changeCount: pasteboard.changeCount)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(appState: appState)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkForUpdates(source: "menu")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
