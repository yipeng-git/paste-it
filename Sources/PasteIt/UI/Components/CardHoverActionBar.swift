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
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func actionButton(
        _ systemName: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.45))
        .disabled(!enabled)
        .help(help)
    }
}
