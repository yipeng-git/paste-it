import AppKit
import SwiftUI

/// Screen frames for visible timeline cards — used to resolve peek-dismiss vs retarget on panel clicks.
/// Touched only from AppKit layout / local mouse monitors on the main thread.
enum ClipCardFrameRegistry {
    nonisolated(unsafe) private static var frames: [UUID: CGRect] = [:]

    static func update(_ id: UUID, frame: CGRect?) {
        if let frame, frame.width > 1, frame.height > 1 {
            frames[id] = frame
        } else {
            frames.removeValue(forKey: id)
        }
    }

    static func remove(_ id: UUID) {
        frames.removeValue(forKey: id)
    }

    static func cardID(atScreenPoint point: CGPoint) -> UUID? {
        for (id, rect) in frames where rect.contains(point) {
            return id
        }
        return nil
    }
}

/// Registers this card's screen frame while the view is alive.
struct ClipCardFrameRegistrar: NSViewRepresentable {
    let id: UUID

    func makeNSView(context: Context) -> ClipCardFrameTrackingView {
        let view = ClipCardFrameTrackingView()
        view.clipID = id
        return view
    }

    func updateNSView(_ nsView: ClipCardFrameTrackingView, context: Context) {
        nsView.clipID = id
        nsView.reportIfNeeded()
    }

    static func dismantleNSView(_ nsView: ClipCardFrameTrackingView, coordinator: ()) {
        if let id = nsView.clipID {
            ClipCardFrameRegistry.remove(id)
        }
        nsView.clipID = nil
    }
}

final class ClipCardFrameTrackingView: NSView {
    var clipID: UUID?
    private var lastReported: CGRect?

    override var isHidden: Bool {
        get { false }
        set {}
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportIfNeeded()
    }

    override func layout() {
        super.layout()
        reportIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportIfNeeded()
    }

    func reportIfNeeded() {
        guard let clipID else { return }
        guard let window else {
            ClipCardFrameRegistry.remove(clipID)
            lastReported = nil
            return
        }
        let windowRect = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        guard lastReported == nil || !screenRect.equalTo(lastReported!) else { return }
        lastReported = screenRect
        ClipCardFrameRegistry.update(clipID, frame: screenRect)
    }
}
