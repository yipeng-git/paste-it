import SwiftUI
import PasteItCore

struct RemovalToastView: View {
    let toast: RemovalFeedback.Toast
    let canUndo: Bool
    let onUndo: (UUID) -> Void
    let onHover: (Bool) -> Void
    var multiline = false
    var layoutSize: CGSize?

    var body: some View {
        Group {
            if multiline {
                row(lineLimit: 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .pasteItToastGlass(cornerRadius: 16)
            } else {
                row(lineLimit: 1)
                    .fixedSize(horizontal: true, vertical: true)
                    .pasteItToastGlass(cornerRadius: 22)
            }
        }
        .frame(width: layoutSize?.width, height: layoutSize?.height)
        .background(ClearHostingBackground())
        .onHover(perform: onHover)
        .accessibilityElement(children: .contain)
    }

    private func row(lineLimit: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(true)
            Text(toast.message)
                .foregroundStyle(.white)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .help(toast.message)
            if let removalID = toast.removalID, canUndo {
                Button { onUndo(removalID) } label: {
                    Text(L10n.tr("removal.undoShort", default: "Undo"))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .contentShape(Capsule())
                }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(RemovalToastUndoStyle())
                    .modifier(ToastFirstClick())
                    .foregroundStyle(.white)
                    .fixedSize()
                    .help(L10n.tr("removal.undoHelp", default: "Undo recent removals for 30 seconds (⌘Z)."))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: lineLimit == 1 ? 44 : 56)
    }
}

private struct ToastFirstClick: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            // The toast never becomes key: the first click must perform Undo.
            content.allowsWindowActivationEvents(true)
        } else {
            // Preserve AppKit's native first-click behavior on macOS 14.
            content.buttonStyle(.borderless)
        }
    }
}

/// Highlight the action inside the shared glass surface, without a second glass layer.
private struct RemovalToastUndoStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.28 : isHovered ? 0.16 : 0.08), in: Capsule())
            .overlay {
                if contrast == .increased && (isHovered || configuration.isPressed) {
                    Capsule().strokeBorder(.white, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
