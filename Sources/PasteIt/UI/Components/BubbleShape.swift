import SwiftUI

// Preview bubble uses the same Liquid Glass chrome as the timeline panel.
// Edge definition comes from native `.glassEffect` (no custom stroke).
extension View {
    @ViewBuilder
    func pasteItBubbleGlass() -> some View {
        pasteItPanelGlass()
    }
}
