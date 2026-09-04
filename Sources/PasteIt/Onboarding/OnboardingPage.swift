import Foundation
import PasteItCore

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
        case .capture: return L10n.tr("onboarding.capture.title", default: "Copy to save")
        case .paste: return L10n.tr("onboarding.paste.title", default: "Pick from the timeline")
        case .browse: return L10n.tr("onboarding.browse.title", default: "Preview & edit")
        case .organize: return L10n.tr("onboarding.organize.title", default: "Multi-select paste")
        case .stack: return L10n.tr("onboarding.stack.title", default: "Paste Stack")
        }
    }

    var caption: String {
        switch self {
        case .capture: return L10n.tr("onboarding.capture.caption", default: "Copy anything — Paste It saves it and flashes ⌘C in the menu bar.")
        case .paste: return L10n.tr("onboarding.paste.caption", default: "⇧⌘V opens history. Double-click a clip, then ⌘V — or ⌃⌘V to paste without formatting.")
        case .browse: return L10n.tr("onboarding.browse.caption", default: "Press Space to preview above the timeline. Click the text to edit.")
        case .organize: return L10n.tr("onboarding.organize.caption", default: "⌘-click several clips, then press Return to paste them in order.")
        case .stack: return L10n.tr("onboarding.stack.caption", default: "⇧⌘C opens a queue on the right. Copy several things, then ⌘V in the target app to paste them one by one.")
        }
    }

    var stepLabels: [String] {
        switch self {
        case .capture: return [
            L10n.tr("onboarding.step.copy", default: "Copy"),
            L10n.tr("onboarding.step.saved", default: "Saved"),
        ]
        case .paste: return [
            L10n.tr("onboarding.step.open", default: "Open"),
            L10n.tr("onboarding.step.doubleClick", default: "Double-click"),
            L10n.tr("onboarding.step.paste", default: "Paste"),
            L10n.tr("onboarding.step.plain", default: "Plain"),
        ]
        case .browse: return [
            L10n.tr("onboarding.step.space", default: "Space"),
            L10n.tr("onboarding.step.preview", default: "Preview"),
            L10n.tr("onboarding.step.edit", default: "Edit"),
        ]
        case .organize: return [
            L10n.tr("onboarding.step.cmdClick", default: "⌘-click"),
            L10n.tr("onboarding.step.order", default: "Order"),
            L10n.tr("onboarding.step.return", default: "Return"),
        ]
        case .stack: return ["⇧⌘C", L10n.tr("onboarding.step.copy", default: "Copy"), "⌘V"]
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
