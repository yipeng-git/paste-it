import AppKit
import SwiftUI

/// Reset the native offset without changing the identity of the lazy card strip.
struct TimelineScrollReset: NSViewRepresentable {
    let request: Int

    func makeNSView(context: Context) -> ResetView { ResetView() }

    func updateNSView(_ view: ResetView, context: Context) {
        view.request = request
        view.scheduleReset()
    }

    final class ResetView: NSView {
        var request = 0
        private var appliedRequest: Int?
        private var isScheduled = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleReset()
        }

        func scheduleReset() {
            guard appliedRequest != request, !isScheduled else { return }
            isScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScheduled = false
                guard let scroll = self.enclosingScrollView else { return }
                var origin = scroll.contentView.bounds.origin
                origin.x = -scroll.contentInsets.left
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
                self.appliedRequest = self.request
            }
        }
    }
}
