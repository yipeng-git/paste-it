import AppKit
import Foundation
import SwiftData
import Testing
import PasteItCore
@testable import PasteIt

@MainActor
@Suite("Product experience recovery", .serialized)
struct ProductExperienceTests {
    @MainActor private final class Fixture {
        let suite = "PasteIt-UX-Tests-\(UUID())"
        let defaults: UserDefaults
        let settings: AppSettings
        let store: HistoryStore
        let pasteboard = NSPasteboard.withUniqueName()
        let paste: PasteController

        init() {
            defaults = UserDefaults(suiteName: suite)!
            settings = AppSettings(defaults: defaults)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("PasteItEphemeral-UX-\(UUID())")
            store = HistoryStore(ephemeralBlobRoot: root, settings: settings)
            paste = PasteController(blobStore: store.blobStore, pasteboard: pasteboard)
        }

        func close() {
            store.discardRemovalUndo()
            store.destroyEphemeralFiles()
            defaults.removePersistentDomain(forName: suite)
            pasteboard.releaseGlobally()
        }

        func clip(_ text: String, age: TimeInterval = 0, type: ClipType = .text) -> ClipItem {
            let item = ClipItem(createdAt: Date().addingTimeInterval(-age), title: text,
                plainText: text, primaryType: type, pasteboardTypes: [], contentHash: text)
            store.context.insert(item)
            try! store.context.save()
            store.refresh()
            return item
        }
    }

    @Test func preferenceMigrationSurvivesReinitialization() {
        let f = Fixture()
        defer { f.close() }
        f.defaults.set("legacy", forKey: "timelinePrimaryAction")
        f.settings.migratePrimaryAction()
        #expect(f.settings.timelinePrimaryAction == .paste)
        #expect(f.defaults.string(forKey: "timelinePrimaryAction") == "paste")
        f.settings.timelinePrimaryAction = .copyOnly
        let reopened = AppSettings(defaults: f.defaults)
        reopened.migratePrimaryAction()
        #expect(reopened.timelinePrimaryAction == .copyOnly)
    }

    @Test func staleToastCannotUndoAnotherRemoval() throws {
        let f = Fixture()
        defer { f.close() }
        let older = f.clip("Older removal")
        let newer = f.clip("Newer removal")
        #expect(f.store.removeFromTab(older, tab: .timeline))
        let olderRemovalID = try #require(f.store.latestRemovalID)
        #expect(f.store.removeFromTab(newer, tab: .timeline))
        let newerRemovalID = try #require(f.store.latestRemovalID)
        #expect(f.store.undoLastRemoval(expectedID: olderRemovalID) == nil)
        #expect(f.store.undoLastRemoval(expectedID: newerRemovalID)?.item.plainText == "Newer removal")
        #expect(f.store.undoLastRemoval(expectedID: newerRemovalID) == nil)
        #expect(f.store.latestRemovalID == olderRemovalID)
        #expect(f.store.undoLastRemoval()?.item.plainText == "Older removal")
    }

    @Test func scopedFeedbackNamesFolderAndToastDismissalKeepsUndo() throws {
        let f = Fixture()
        defer { f.close() }
        let state = AppState(settings: f.settings, historyStore: f.store, searchService: SearchService())
        let clip = f.clip("Synthetic saved clip")
        let folder = f.store.createPinboard(name: "Work 工作 100%")
        f.store.pin(clip, to: folder)
        #expect(state.removalTitle(for: .folder(folder.id)).contains(folder.name))
        state.unpin(clip, from: folder)
        #expect(state.removalFeedback.toast?.message.contains(folder.name) == true)
        let removalID = try #require(state.removalFeedback.toast?.removalID)
        #expect(removalID == f.store.latestRemovalID)
        state.removalFeedback.dismiss()
        #expect(f.store.canUndoRemoval)
        state.undoLastRemoval(expectedID: removalID)
        #expect(clip.pinboardIDs.contains(folder.id))
        #expect(state.removalFeedback.toast != nil)
        #expect(state.removalFeedback.toast?.removalID == nil)
        state.togglePinned(clip)
        state.togglePinned(clip)
        #expect(state.removalFeedback.toast?.removalID == f.store.latestRemovalID)
        f.store.expireRemovalUndo(now: Date().addingTimeInterval(31))
        #expect(f.store.latestRemovalID == nil)
        #expect(!f.store.canUndoRemoval)
        state.removalFeedback.dismiss()
    }

    @Test func missingMediaDoesNotReplaceClipboardOrReportMutation() async {
        let f = Fixture()
        defer { f.close() }
        f.pasteboard.setString("Synthetic original", forType: .string)
        let change = f.pasteboard.changeCount
        var mutations = 0
        f.paste.onPasteboardMutation = { _ in mutations += 1 }
        let image = f.clip("Synthetic missing image", type: .image)
        image.blobRelativePath = "Blobs/missing.png"
        #expect(!(await f.paste.copyToPasteboardAsync(image)))
        let file = f.clip("Synthetic missing file", type: .file)
        file.fileURLString = f.store.blobStore.rootURL.appendingPathComponent("missing.txt").absoluteString
        #expect(!f.paste.copyToPasteboard(file))
        #expect(f.pasteboard.string(forType: .string) == "Synthetic original")
        #expect(f.pasteboard.changeCount == change)
        #expect(mutations == 0)
    }

    @Test func supportedWritesPreserveFormatsAndSuppressCapture() async throws {
        let f = Fixture()
        defer { f.close() }
        var lastMutation: Int?
        f.paste.onPasteboardMutation = { lastMutation = $0 }
        let rich = f.clip("Synthetic rich", type: .richText)
        rich.rtfData = NSAttributedString(string: "Synthetic rich").rtf(from: NSRange(location: 0, length: 14), documentAttributes: [:])
        #expect(f.paste.copyToPasteboard(rich))
        #expect(f.pasteboard.data(forType: .rtf) != nil)
        #expect(lastMutation == f.pasteboard.changeCount)
        #expect(f.paste.copyToPasteboard(rich, mode: .plainText))
        #expect(f.pasteboard.data(forType: .rtf) == nil)
        #expect(f.pasteboard.string(forType: .string) == "Synthetic rich")
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let image = f.clip("Synthetic image", type: .image)
        image.blobRelativePath = try f.store.blobStore.store(data: data, preferredExtension: "png")
        #expect(await f.paste.copyToPasteboardAsync(image))
        #expect(f.pasteboard.data(forType: .png) == data)
        let file = f.clip("Synthetic file", type: .file)
        let url = f.store.blobStore.rootURL.appendingPathComponent("synthetic.txt")
        try Data("Synthetic file".utf8).write(to: url)
        file.fileURLString = url.absoluteString
        #expect(f.paste.copyToPasteboard(file))
        #expect(f.pasteboard.string(forType: .fileURL) == url.absoluteString)
        #expect(lastMutation == f.pasteboard.changeCount)
    }

    @Test func undoRestoresTextAndTimelineOrder() throws {
        let f = Fixture()
        defer { f.close() }
        _ = f.clip("Older", age: 30)
        let middle = f.clip("Middle", age: 20)
        _ = f.clip("Newer", age: 10)
        let originalIDs = f.store.clips.map(\.id)
        #expect(f.store.removeFromTab(middle, tab: .timeline))
        #expect(f.store.clips.count == 2)
        #expect(f.store.canUndoRemoval)
        let restored = try #require(f.store.undoLastRemoval())
        #expect(restored.item.plainText == "Middle")
        #expect(f.store.clips.map(\.id) == originalIDs)
        #expect(!f.store.canUndoRemoval)
    }

    @Test func removalScopeAndMembershipRecovery() throws {
        let f = Fixture()
        defer { f.close() }
        let clip = f.clip("Saved")
        let pinned = f.store.pinnedPinboard
        let folder = f.store.createPinboard(name: "Synthetic Folder")
        f.store.pin(clip, to: pinned)
        f.store.pin(clip, to: folder)
        #expect(f.store.removeFromTab(clip, tab: .timeline))
        #expect(clip.isHiddenFromTimeline)
        #expect(Set(clip.pinboardIDs) == [pinned.id, folder.id])
        #expect(f.store.removeFromTab(clip, tab: .pinned))
        #expect(clip.pinboardIDs == [folder.id])
        let clipID = clip.id
        #expect(f.store.removeFromTab(clip, tab: .folder(folder.id)))
        #expect(f.store.clips.isEmpty)
        let restored = try #require(f.store.undoLastRemoval()).item
        #expect(restored.id == clipID)
        #expect(restored.pinboardIDs == [folder.id])
        #expect(folder.itemIDs == [clipID])
        _ = f.store.undoLastRemoval()
        #expect(Set(restored.pinboardIDs) == [pinned.id, folder.id])
        _ = f.store.undoLastRemoval()
        #expect(!restored.isHiddenFromTimeline)
    }

    @Test func undoProtectsAttachmentUntilExpiry() throws {
        let f = Fixture()
        defer { f.close() }
        let image = f.clip("Protected synthetic image", type: .image)
        let data = Data(repeating: 1, count: 1024)
        let path = try f.store.blobStore.store(data: data, preferredExtension: "png")
        image.blobRelativePath = path
        #expect(f.store.removeFromTab(image, tab: .timeline))
        f.store.blobStore.prune(maxMegabytes: 0)
        #expect(f.store.blobStore.data(for: path) == data)
        f.store.expireRemovalUndo(now: Date().addingTimeInterval(31))
        #expect(!f.store.canUndoRemoval)
        #expect(f.store.undoLastRemoval() == nil)
        f.store.blobStore.prune(maxMegabytes: 0)
        #expect(f.store.blobStore.data(for: path) == nil)
    }

    @Test func recopyBeforeUndoDoesNotDuplicateContent() throws {
        let f = Fixture()
        defer { f.close() }
        let item = f.clip("Synthetic recopy")
        #expect(f.store.removeFromTab(item, tab: .timeline))
        let newer = f.clip("Synthetic recopy")
        let restored = try #require(f.store.undoLastRemoval()).item
        #expect(restored.id == newer.id)
        #expect(f.store.clips.count == 1)
    }

    @Test func cleanupUsesReviewedIDsKeepsSavedAndInvalidatesUndo() {
        let f = Fixture()
        defer { f.close() }
        let saved = f.clip("Saved")
        let folder = f.store.createPinboard(name: "Synthetic Saved")
        f.store.pin(saved, to: folder)
        let ordinary = f.clip("Ordinary")
        let removed = f.clip("Undo candidate")
        #expect(f.store.removeFromTab(removed, tab: .timeline))
        let ids = Set(f.store.clearHistoryCandidates(keepSaved: true).map(\.id))
        #expect(ids == [ordinary.id])
        let newCapture = f.clip("Captured while confirming")
        #expect(f.store.deleteReviewedClips(ids: ids, keepSaved: true))
        #expect(Set(f.store.clips.map(\.id)) == [saved.id, newCapture.id])
        #expect(!f.store.canUndoRemoval)
        #expect(folder.itemIDs == [saved.id])
        #expect(f.store.deleteReviewedClips(ids: [saved.id], keepSaved: false))
        #expect(folder.itemIDs.isEmpty)
    }

    @Test func retentionPreviewIsReadOnlyAndExcludesSavedClips() {
        let f = Fixture()
        defer { f.close() }
        let old = f.clip("Old", age: 3 * 86400)
        let saved = f.clip("Old saved", age: 3 * 86400)
        f.store.pinToPinnedBoard(saved)
        _ = f.clip("Recent")
        let ids = f.store.retentionCandidates(.oneDay).map(\.id)
        #expect(ids == [old.id])
        #expect(f.settings.keepHistory == .forever)
        #expect(f.store.clips.count == 3)
    }

    @Test func deletingEverywhereDoesNotCancelUnrelatedUndo() throws {
        let f = Fixture()
        defer { f.close() }
        let recoverable = f.clip("Keep undo")
        let doomed = f.clip("Delete everywhere")
        #expect(f.store.removeFromTab(recoverable, tab: .timeline))
        f.store.deleteEverywhere(doomed)
        #expect(f.store.canUndoRemoval)
        #expect(try #require(f.store.undoLastRemoval()).item.plainText == "Keep undo")
    }

    @Test func undoAfterFolderDeletionReturnsToHistory() throws {
        let f = Fixture()
        defer { f.close() }
        let item = f.clip("Folder removed during undo")
        let folder = f.store.createPinboard(name: "Temporary synthetic folder")
        f.store.pin(item, to: folder)
        #expect(f.store.removeFromTab(item, tab: .timeline))
        #expect(f.store.removeFromTab(item, tab: .folder(folder.id)))
        f.store.deletePinboard(folder)
        let restored = try #require(f.store.undoLastRemoval())
        #expect(restored.tab == .timeline)
        #expect(restored.item.pinboardIDs.isEmpty)
        #expect(!restored.item.isHiddenFromTimeline)
    }

    @Test func undoDoesNotDisplaceNewCapturesOrNewPins() throws {
        let f = Fixture()
        defer { f.close() }
        let older = f.clip("Older removed clip", age: 60)
        let olderID = older.id
        #expect(f.store.removeFromTab(older, tab: .timeline))
        let newer = f.clip("New capture")
        _ = f.store.undoLastRemoval()
        #expect(f.store.clips.map(\.id) == [newer.id, olderID])
        let restored = try #require(f.store.clips.last)
        let board = f.store.pinnedPinboard
        f.store.pin(restored, to: board)
        #expect(f.store.removeFromTab(restored, tab: .pinned))
        f.store.pin(newer, to: board)
        _ = f.store.undoLastRemoval()
        #expect(board.itemIDs == [newer.id, olderID])
    }
}
