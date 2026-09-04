import SwiftUI

/// Shared panel/control chrome. Liquid Glass on macOS 26+; material fallback below.
enum PasteItGlass {
    static let panelShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    static let controlShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    static let cardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    static let stackRowShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    static let menuSelectionShape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    static let previewInsetShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    static let popoverShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
}

extension View {
    /// Panel chrome: Liquid Glass that refracts the desktop behind the floating timeline.
    /// Clip before glass so child materials cannot paint outside the rounded silhouette.
    @ViewBuilder
    func pasteItPanelGlass() -> some View {
        if #available(macOS 26, *) {
            clipShape(PasteItGlass.panelShape)
                .glassEffect(.regular, in: PasteItGlass.panelShape)
        } else {
            clipShape(PasteItGlass.panelShape)
                .background(.ultraThinMaterial, in: PasteItGlass.panelShape)
        }
    }

    /// Compact control chrome (search field, icon buttons, etc.).
    @ViewBuilder
    func pasteItControlGlass() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: PasteItGlass.controlShape)
        } else {
            background(.ultraThinMaterial, in: PasteItGlass.controlShape)
        }
    }

    /// Capsule control chrome (tab picker, hover toolbar).
    @ViewBuilder
    func pasteItCapsuleGlass() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Timeline cards sitting on the glass panel.
    @ViewBuilder
    func pasteItCardGlass() -> some View {
        if #available(macOS 26, *) {
            clipShape(PasteItGlass.cardShape)
                .glassEffect(.regular, in: PasteItGlass.cardShape)
        } else {
            background(Color(nsColor: .windowBackgroundColor), in: PasteItGlass.cardShape)
        }
    }

    /// Paste Stack queue rows.
    @ViewBuilder
    func pasteItStackRowGlass(isHighlighted: Bool = false) -> some View {
        if #available(macOS 26, *) {
            clipShape(PasteItGlass.stackRowShape)
                .glassEffect(
                    isHighlighted ? .regular.tint(.accentColor) : .regular,
                    in: PasteItGlass.stackRowShape
                )
        } else {
            background(
                isHighlighted
                    ? Color.accentColor.opacity(0.10)
                    : Color(nsColor: .windowBackgroundColor).opacity(0.72),
                in: PasteItGlass.stackRowShape
            )
        }
    }

    /// Inset preview surface inside the Space bubble (image viewport, editors).
    @ViewBuilder
    func pasteItPreviewInsetGlass() -> some View {
        if #available(macOS 26, *) {
            clipShape(PasteItGlass.previewInsetShape)
                .glassEffect(.regular, in: PasteItGlass.previewInsetShape)
        } else {
            background(Color.primary.opacity(0.04), in: PasteItGlass.previewInsetShape)
        }
    }

    /// Toolbar / title-bar control: Liquid Glass button on macOS 26+, borderless below.
    @ViewBuilder
    func pasteItGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.borderless)
        }
    }

    /// Popover chrome (filter menu, new-folder form, …).
    @ViewBuilder
    func pasteItPopoverChrome() -> some View {
        if #available(macOS 26, *) {
            presentationBackground {
                PasteItGlass.popoverShape
                    .fill(.clear)
                    .glassEffect(.regular, in: PasteItGlass.popoverShape)
            }
        } else {
            presentationBackground(.ultraThinMaterial)
        }
    }
}

/// Hover highlight for compact icon buttons (card action bar).
@ViewBuilder
func pasteItActionBarButtonHighlight(isHovered: Bool, enabled: Bool = true) -> some View {
    if isHovered {
        if #available(macOS 26, *) {
            Circle()
                .fill(.clear)
                .glassEffect(
                    enabled ? .regular.interactive() : .regular,
                    in: Circle()
                )
        } else {
            Circle()
                .fill(Color.primary.opacity(enabled ? 0.14 : 0.08))
        }
    }
}

/// Selection chips inside a glass capsule group (tabs, segmented controls).
@ViewBuilder
func pasteItSegmentHighlight(
    isSelected: Bool,
    in namespace: Namespace.ID? = nil,
    matchedID: String = "pasteItSegmentHighlight"
) -> some View {
    if isSelected {
        if let namespace {
            segmentHighlightBody()
                .matchedGeometryEffect(id: matchedID, in: namespace)
        } else {
            segmentHighlightBody()
        }
    }
}

@ViewBuilder
private func segmentHighlightBody() -> some View {
    if #available(macOS 26, *) {
        Capsule()
            .fill(.clear)
            // Slight primary tint lifts the pill off the outer capsule glass.
            .glassEffect(.regular.tint(Color.primary.opacity(0.09)).interactive(), in: Capsule())
    } else {
        Capsule()
            .fill(Color.primary.opacity(0.16))
    }
}

/// Popover / menu row selection.
@ViewBuilder
func pasteItMenuRowHighlight(isSelected: Bool) -> some View {
    if isSelected {
        if #available(macOS 26, *) {
            PasteItGlass.menuSelectionShape
                .fill(.clear)
                .glassEffect(.regular, in: PasteItGlass.menuSelectionShape)
        } else {
            PasteItGlass.menuSelectionShape
                .fill(Color.primary.opacity(0.08))
        }
    }
}

/// Small status chip (e.g. Stack "Collecting").
@ViewBuilder
func pasteItStatusCapsule(tint: Color) -> some View {
    if #available(macOS 26, *) {
        Capsule()
            .fill(.clear)
            .glassEffect(.regular.tint(tint), in: Capsule())
    } else {
        Capsule()
            .fill(tint.opacity(0.14))
    }
}
