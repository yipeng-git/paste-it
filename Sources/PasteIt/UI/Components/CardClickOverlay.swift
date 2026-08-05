import AppKit
import SwiftUI

/// AppKit overlay that owns card click handling so single-click selection is
/// immediate (no SwiftUI double-tap delay). ⌘-click multi-selects; plain
/// click selects; double-click stages. Non-command hits still return `nil`
/// from `hitTest` so SwiftUI `.draggable` / context menus keep working —
/// we only observe `leftMouseDown` and fire callbacks.
struct CardClickOverlay: NSViewRepresentable {
    var onSingleClick: () -> Void
    var onDoubleClick: () -> Void
    var onCommandClick: () -> Void

    func makeNSView(context: Context) -> CardCommandClickNSView {
        let view = CardCommandClickNSView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        view.onCommandClick = onCommandClick
        return view
    }

    func updateNSView(_ nsView: CardCommandClickNSView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onCommandClick = onCommandClick
    }
}

final class CardCommandClickNSView: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onCommandClick: (() -> Void)?

    /// `hitTest` can run many times for one event; fire callbacks once per timestamp.
    private var lastHandledEventTimestamp: TimeInterval = -1

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinate system.
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }

        guard let event = NSApp.currentEvent else { return nil }

        let isCommand = event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.control)

        // ⌘-click: steal the event so SwiftUI gestures never see it.
        if isCommand {
            switch event.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
                return self
            default:
                return nil
            }
        }

        // Plain left click: observe without stealing (keeps `.draggable` alive).
        // Defer callbacks out of hitTest — mutating app state here is unsafe.
        if event.type == .leftMouseDown,
           !event.modifierFlags.contains(.control),
           event.timestamp != lastHandledEventTimestamp
        {
            lastHandledEventTimestamp = event.timestamp
            let clickCount = event.clickCount
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if clickCount >= 2 {
                    self.onDoubleClick?()
                } else {
                    self.onSingleClick?()
                }
            }
        }

        return nil
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
