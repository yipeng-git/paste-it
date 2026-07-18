import AppKit
import SwiftUI

/// Walks the AppKit hosting hierarchy and clears opaque backgrounds that otherwise
/// fill the rectangular "ears" outside a rounded liquid-glass panel.
struct ClearHostingBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> ClearHostingBackgroundView {
        ClearHostingBackgroundView()
    }

    func updateNSView(_ nsView: ClearHostingBackgroundView, context: Context) {
        nsView.clearOpaqueBackgrounds()
    }
}

final class ClearHostingBackgroundView: NSView {
    override var isHidden: Bool {
        get { false }
        set {}
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearOpaqueBackgrounds()
    }

    override func layout() {
        super.layout()
        clearOpaqueBackgrounds()
    }

    func clearOpaqueBackgrounds() {
        if let window {
            window.isOpaque = false
            window.backgroundColor = .clear
        }

        var cursor: NSView? = self
        while let view = cursor {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.isOpaque = false
            // NSHostingView / theme frames sometimes keep an AppKit draw flag.
            if view.responds(to: Selector(("setDrawsBackground:"))) {
                view.setValue(false, forKey: "drawsBackground")
            }
            cursor = view.superview
        }

        if let content = window?.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
            content.layer?.isOpaque = false
        }
    }
}

@MainActor
enum PanelCornerMask {
    static let radius: CGFloat = 24

    static func apply(to view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
