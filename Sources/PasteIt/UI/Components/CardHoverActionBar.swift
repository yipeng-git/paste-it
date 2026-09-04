import SwiftUI

/// Compact hover toolbar for timeline cards (Copy / Edit / Pin / Delete).
struct CardHoverActionBar: View {
    var isPinned: Bool
    /// When false, Edit stays visible but dimmed / non-interactive.
    var canEdit: Bool
    var deleteHelp: String
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            actionButton("doc.on.doc", help: "Copy to Clipboard", action: onCopy)
            actionButton(
                "pencil",
                help: canEdit ? "Edit" : "Editing isn’t available for this clip",
                enabled: canEdit,
                action: onEdit
            )
            actionButton(
                isPinned ? "pin.slash" : "pin",
                help: isPinned ? "Unpin" : "Pin",
                action: onPin
            )
            actionButton("trash", help: deleteHelp, action: onDelete)
        }
        .padding(4)
        .pasteItCapsuleGlass()
        .modifier(CardHoverActionBarChrome())
    }

    private func actionButton(
        _ systemName: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        ActionBarButton(
            systemName: systemName,
            help: help,
            enabled: enabled,
            action: action
        )
    }
}

private struct ActionBarButton: View {
    let systemName: String
    let help: String
    var enabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: isHovered && enabled ? .bold : .semibold))
                .frame(width: 28, height: 28)
                .background {
                    pasteItActionBarButtonHighlight(isHovered: isHovered, enabled: enabled)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            enabled
                ? Color.primary.opacity(isHovered ? 1 : 0.88)
                : Color.secondary.opacity(0.45)
        )
        .disabled(!enabled)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

/// Legacy stroke/shadow only on pre–Liquid Glass macOS.
private struct CardHoverActionBarChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
    }
}
