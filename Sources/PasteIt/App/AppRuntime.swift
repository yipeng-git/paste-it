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
            editSelected: { [appState, panelController] in
                guard panelController.isVisible || appState.editingClip != nil else {
                    return false
                }
                return appState.beginEditingSelectedClip()
            }
        )
        appState.pasteStackController = pasteStackController
        appState.panelController = panelController
        panelController.detachedWindowController = detachedWindowController
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
        LaunchAtLoginManager.syncAtStartup(enabled: settings.launchAtLogin)
        // Retain Sparkle updater for automatic background checks.
        _ = UpdateChecker.shared
        Analytics.start(enabled: settings.analyticsEnabled)

        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [settings] in
                guard !settings.hasCompletedOnboarding else { return }
                OnboardingWindowController.shared.show(settings: settings, source: "first_launch")
            }
        }

        applyAgentAPIEnabled(settings.agentAPIEnabled)
    }

    func stop() {
        Analytics.stop()
        AgentAPIServer.shared.stop()
        pasteboardMonitor.stop()
        hotkeyManager.stop()
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Paste It"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.menu = nil
        statusItem = item
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        statusItem?.button?.title = pasteStackController.statusTitle
        statusItem?.button?.toolTip = "Paste It\nRight-click for menu"
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
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = action == nil ? nil : self
        item.isEnabled = enabled
        if shiftCommand, !keyEquivalent.isEmpty {
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

    @objc private func clearPasteStack() {
        pasteStackController.close()
        refreshStatusItem()
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
