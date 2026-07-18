import AppKit
import Foundation

/// Slide-from-below frame for panel show/hide animations.
///
/// Slides fully offscreen when nothing is below `screen`. Only when a display
/// sits vertically below do we clamp to the screen edge (so the panel doesn't
/// slide onto the adjacent display) — callers pair the clamped, shorter slide
/// with an alpha fade so the dismissal still reads as one motion.
func panelSlideOffscreenFrame(
    from onscreen: NSRect,
    screen: NSScreen
) -> NSRect {
    var frame = onscreen
    frame.origin.y -= onscreen.height
    if screenExistsBelow(screen) {
        frame.origin.y = max(frame.origin.y, screen.frame.minY)
    }
    return frame
}

private func screenExistsBelow(_ screen: NSScreen) -> Bool {
    NSScreen.screens.contains { other in
        guard other !== screen else { return false }
        let overlapsHorizontally = other.frame.maxX > screen.frame.minX
            && other.frame.minX < screen.frame.maxX
        return overlapsHorizontally && other.frame.minY < screen.frame.minY
    }
}

extension String {
    var looksLikeURL: Bool {
        guard let url = URL(string: self.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "file", "mailto"].contains(scheme)
    }
}
