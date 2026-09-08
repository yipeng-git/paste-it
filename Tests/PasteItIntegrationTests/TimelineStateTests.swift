import Combine
import Foundation
import Testing
@testable import PasteIt
import PasteItCore

@MainActor
@Suite("Timeline state integration", .serialized)
struct TimelineStateTests {
    private func fixture(count: Int = 40) -> (HistoryStore, AppState) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PasteItEphemeral-Tests-\(UUID())")
        let settings = AppSettings()
        let store = HistoryStore(ephemeralBlobRoot: root, settings: settings)
        for n in 0..<count {
            store.context.insert(ClipItem(createdAt: Date(timeIntervalSince1970: Double(n)),
                title: "Synthetic \(n)", plainText: "Synthetic \(n)", primaryType: .text,
                pasteboardTypes: ["public.utf8-plain-text"], contentHash: "synthetic-\(n)"))
        }
        store.refresh()
        return (store, AppState(settings: settings, historyStore: store, searchService: SearchService()))
    }

    private func settleNotifications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func promotionCoalescesMultipleArrayMutations() async throws {
        let (store, _) = fixture()
        defer { store.destroyEphemeralFiles() }
        await settleNotifications()
        var notifications = 0
        let token = store.changes.sink { _ in notifications += 1 }
        let item = try #require(store.clips.last)
        store.promoteToFront(item)
        await settleNotifications()
        #expect(notifications == 1)
        #expect(store.clips.first?.id == item.id)
        token.cancel()
    }

    @Test func tabPublishesCompleteResultsAndRapidSearchKeepsNewestRequest() async throws {
        let (store, state) = fixture()
        defer { store.destroyEphemeralFiles() }
        let board = store.pinnedPinboard
        for item in store.clips { store.pin(item, to: board) }
        await settleNotifications()
        var publications = 0
        let token = state.$visibleClips.dropFirst().sink { _ in publications += 1 }
        state.selectedTab = .pinned
        await state.awaitSearchResults()
        #expect(state.visibleClips.count == 40)
        #expect(publications <= 2)
        state.setQueryFromExternal("no match")
        state.setQueryFromExternal("Synthetic 39")
        await state.awaitSearchResults()
        #expect(state.visibleClips.map(\.plainText) == ["Synthetic 39"])
        state.clearSearch()
        await state.awaitSearchResults()
        #expect(state.visibleClips.count == 40)
        token.cancel()
    }

    @Test func contentEditsRefreshSearchAndCardSummary() async throws {
        let (store, state) = fixture(count: 2)
        defer { store.destroyEphemeralFiles() }
        await settleNotifications()
        let item = try #require(store.clips.first)
        let before = ClipVisualCache.shared.cardText(for: item)
        state.setQueryFromExternal("replacement")
        await state.awaitSearchResults()
        #expect(state.visibleClips.isEmpty)
        store.update(item, plainText: "replacement café")
        await settleNotifications()
        await state.awaitSearchResults()
        #expect(state.visibleClips.map(\.id) == [item.id])
        let after = ClipVisualCache.shared.cardText(for: item)
        #expect(after.text == "replacement café")
        #expect(before != after)
        store.delete(item)
        await settleNotifications()
        await state.awaitSearchResults()
        #expect(state.visibleClips.isEmpty)
        #expect(state.selectedClipID == nil)
    }
}
