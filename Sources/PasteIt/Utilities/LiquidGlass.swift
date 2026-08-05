import SwiftUI

/// Shared panel/control chrome. Liquid Glass on macOS 26+; material fallback below.
enum PasteItGlass {
    static let panelShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    static let controlShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    static let cardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
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

    /// Compact control chrome (search field, etc.).
    @ViewBuilder
    func pasteItControlGlass() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: PasteItGlass.controlShape)
        } else {
            background(.ultraThinMaterial, in: PasteItGlass.controlShape)
        }
    }

    /// Capsule control chrome (tab picker).
    @ViewBuilder
    func pasteItCapsuleGlass() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
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
}
