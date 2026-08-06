import Foundation

enum OnboardingFlow: String {
    case install
    case update
}

enum OnboardingPageID: Int, CaseIterable, Identifiable {
    /// Copy in any app → history + menu-bar flash.
    case capture
    /// ⇧⌘V open timeline → select → paste into another app (result visible).
    case paste
    /// Space preview bubble → click to edit in place.
    case browse
    /// ⌘-click multi-select → Return to paste in order.
    case organize

    var id: Int { rawValue }

    var analyticsName: String {
        switch self {
        case .capture: return "capture"
        case .paste: return "paste"
        case .browse: return "browse"
        case .organize: return "organize"
        }
    }

    var title: String {
        switch self {
        case .capture: return "Copy to save"
        case .paste: return "Pick from the timeline"
        case .browse: return "Preview & edit"
        case .organize: return "Multi-select paste"
        }
    }

    var caption: String {
        switch self {
        case .capture: return "Copy anything — Paste It saves it and flashes ⌘C in the menu bar."
        case .paste: return "⇧⌘V opens history. Double-click a clip, then ⌘V in any app."
        case .browse: return "Press Space to preview above the timeline. Click the text to edit."
        case .organize: return "⌘-click several clips, then press Return to paste them in order."
        }
    }

    var stepLabels: [String] {
        switch self {
        case .capture: return ["Copy", "Saved"]
        case .paste: return ["Open", "Double-click", "Paste"]
        case .browse: return ["Space", "Preview", "Edit"]
        case .organize: return ["⌘-click", "Order", "Return"]
        }
    }

    static func pages(for flow: OnboardingFlow) -> [OnboardingPageID] {
        // This content pack rebuilt the whole tutorial — returning users see the
        // same 4-page flow once (via what's-new gate), not only the feature pages.
        switch flow {
        case .install, .update:
            return [.capture, .paste, .browse, .organize]
        }
    }
}
