import Foundation

public enum TimelinePrimaryAction: String, CaseIterable, Identifiable, Sendable {
    case paste
    case copyOnly

    public var id: String { rawValue }

    public static func initialValue(saved: String?) -> Self {
        if let saved, let value = Self(rawValue: saved) { return value }
        return .paste
    }

    public var shouldPaste: Bool { self == .paste }

    public var title: String {
        switch self {
        case .paste: L10n.tr("action.paste", default: "Direct Paste")
        case .copyOnly: L10n.tr("action.copyOnly", default: "Copy Only")
        }
    }
}
