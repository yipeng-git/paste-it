import Foundation

enum OnboardingFlow: String {
    case install
    case update
}

enum OnboardingPageID: Int, CaseIterable, Identifiable {
    /// Copy in any app → history + menu-bar flash.
    case capture
    /// ⇧⌘V open timeline → select → ⌘V paste → ⌃⌘V paste plain.
    case paste
    /// Space preview bubble → click to edit in place.
    case browse
    /// ⌘-click multi-select → Return to paste in order.
    case organize
    /// ⇧⌘C open stack → copy into the queue → ⌘V in the target app.
    case stack

    var id: Int { rawValue }

    var analyticsName: String {
        switch self {
        case .capture: return "capture"
        case .paste: return "paste"
        case .browse: return "browse"
        case .organize: return "organize"
        case .stack: return "stack"
        }
    }

    var title: String {
        switch self {
        case .capture: return "Copy to save"
        case .paste: return "Pick from the timeline"
        case .browse: return "Preview & edit"
        case .organize: return "Multi-select paste"
        case .stack: return "Paste Stack"
        }
    }

    var caption: String {
        switch self {
        case .capture: return "Copy anything — Paste It saves it and flashes ⌘C in the menu bar."
        case .paste: return "⇧⌘V opens history. Double-click a clip, then ⌘V — or ⌃⌘V to paste without formatting."
        case .browse: return "Press Space to preview above the timeline. Click the text to edit."
        case .organize: return "⌘-click several clips, then press Return to paste them in order."
        case .stack: return "⇧⌘C opens a queue on the right. Copy several things, then ⌘V in the target app to paste them one by one."
        }
    }

    var stepLabels: [String] {
        switch self {
        case .capture: return ["Copy", "Saved"]
        case .paste: return ["Open", "Double-click", "Paste", "Plain"]
        case .browse: return ["Space", "Preview", "Edit"]
        case .organize: return ["⌘-click", "Order", "Return"]
        case .stack: return ["⇧⌘C", "Copy", "⌘V"]
        }
    }

    static func pages(for flow: OnboardingFlow) -> [OnboardingPageID] {
        // Install: full first-run. Update: only the new Stack loop.
        switch flow {
        case .install:
            return [.capture, .paste, .browse, .organize, .stack]
        case .update:
            return [.stack]
        }
    }
}
