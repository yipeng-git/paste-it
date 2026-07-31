import AppKit
import SwiftUI

/// Overlay that steals clicks only while ⌘ is held, so multi-select is immediate
/// and does not wait for SwiftUI's double-click delay. Other clicks pass through.
struct CardClickOverlay: NSViewRepresentable {
    var onCommandClick: () -> Void

    func makeNSView(context: Context) -> CardCommandClickNSView {
        let view = CardCommandClickNSView()
        view.onCommandClick = onCommandClick
        return view
    }

    func updateNSView(_ nsView: CardCommandClickNSView, context: Context) {
        nsView.onCommandClick = onCommandClick
    }
}

final class CardCommandClickNSView: NSView {
    var onCommandClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinate system.
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }

        // Only intercept while ⌘ is held; otherwise pass through to SwiftUI.
        guard let event = NSApp.currentEvent,
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control)
        else {
            return nil
        }

        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return self
        default:
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control)
        else {
            return
        }
        onCommandClick?()
    }
}
