import AppKit
import SwiftUI
import Testing
@testable import PasteIt

@MainActor
@Suite("Removal toast placement and sizing")
struct RemovalToastLayoutTests {
    @Test func displayedChildKeepsMeasuredFrameAndDoesNotTakeFocus() async throws {
        let suite = "PasteIt-ToastWindow-Test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PasteItEphemeral-Toast-\(UUID())")
        let store = HistoryStore(ephemeralBlobRoot: root, settings: settings)
        let state = AppState(settings: settings, historyStore: store, searchService: SearchService())
        let parent = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 800, height: 320),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        parent.ignoresMouseEvents = true
        parent.orderFrontRegardless()
        let keyWindow = NSApp.keyWindow
        let controller = RemovalToastPanelController(appState: state)
        controller.attach(to: parent)
        defer {
            state.removalFeedback.dismiss()
            controller.hide(animated: false)
            parent.orderOut(nil)
            store.discardRemovalUndo()
            store.destroyEphemeralFiles()
            defaults.removePersistentDomain(forName: suite)
        }
        let item = ClipItem(title: "Synthetic", plainText: "Synthetic", primaryType: .text,
                            pasteboardTypes: [], contentHash: "Synthetic")
        store.context.insert(item)
        try store.context.save()
        store.refresh()
        store.removeFromTab(item, tab: .timeline)
        state.removalFeedback.show("Removed from “Work”", removalID: store.latestRemovalID)
        controller.refresh()
        // Native material setup can delay the first animation frame under load.
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if let child = parent.childWindows?.first,
               child.frame.minY == parent.frame.maxY + 12, child.alphaValue == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let child = try #require(parent.childWindows?.first)
        let host = try #require(child.contentViewController as? NSHostingController<RemovalToastView>)
        #expect(!host.rootView.multiline)
        #expect(child.frame.height == 44)
        // AppKit aligns an odd-width floating window to the display pixel grid.
        #expect(abs(child.frame.midX - parent.frame.midX) <= 0.5)
        #expect(child.frame.minY == parent.frame.maxY + 12)
        #expect(!child.canBecomeKey)
        #expect(NSApp.keyWindow === keyWindow)
        #expect(child.ignoresMouseEvents)
        #expect(!child.hasShadow)
        let removalID = try #require(store.latestRemovalID)
        // Exercise the displayed view's action wiring against the temporary store.
        host.rootView.onUndo(removalID)
        #expect(store.clips.contains { $0.id == item.id && !$0.isHiddenFromTimeline })
        #expect(state.removalFeedback.toast?.removalID == nil)
    }

    @Test func sitsAboveParentOnTheSameDisplay() {
        let screen = NSRect(x: -1440, y: 0, width: 1440, height: 900)
        let parent = NSRect(x: -1280, y: 24, width: 1120, height: 320)
        let result = RemovalToastPlacement.frame(size: NSSize(width: 300, height: 44), parent: parent, screen: screen)
        #expect(result.midX == parent.midX)
        #expect(result.minY == parent.maxY + 12)
        #expect(!result.intersects(parent))
    }

    @Test func remainsInsideVisibleScreenNearEdges() {
        let screen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let parent = NSRect(x: 600, y: 260, width: 640, height: 320)
        let result = RemovalToastPlacement.frame(size: NSSize(width: 450, height: 56), parent: parent, screen: screen)
        #expect(screen.insetBy(dx: 12, dy: 12).contains(result))
        #expect(RemovalToastPlacement.maximumWidth(parent: parent, screen: screen) == 450)
    }

    @Test func shortToastFitsContentAndLongToastWrapsWithoutExpandingPanel() {
        let feedback = RemovalFeedback()
        feedback.show("Removed", removalID: UUID())
        let short = RemovalToastView(toast: feedback.toast!, canUndo: true, onUndo: { _ in }, onHover: { _ in })
        let host = NSHostingController(rootView: short)
        let shortSize = host.sizeThatFits(in: NSSize(width: 450, height: 100))
        #expect(shortSize.width < 300)
        #expect(shortSize.height == 44)
        feedback.show(String(repeating: "工作 Project ", count: 20), removalID: UUID())
        host.rootView = RemovalToastView(toast: feedback.toast!, canUndo: true, onUndo: { _ in }, onHover: { _ in }, multiline: true)
        let longSize = host.sizeThatFits(in: NSSize(width: 450, height: 100))
        #expect(longSize.width <= 450)
        #expect(longSize.height == 56)
        feedback.dismiss()
    }
}
