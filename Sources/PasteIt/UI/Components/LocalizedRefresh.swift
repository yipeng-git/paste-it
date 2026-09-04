import SwiftUI

/// Forces a view subtree to re-render when the user changes system / app language.
private struct LocalizedRefreshModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content.background {
            Color.clear.id(appState.localeRevision)
        }
    }
}

private struct LocalizedRefreshFallbackModifier: ViewModifier {
    @State private var tick = 0

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear.id(tick)
            }
            .onReceive(NotificationCenter.default.publisher(for: .pasteItLocaleDidChange)) { _ in
                tick += 1
            }
    }
}

extension View {
    func localizedRefreshTrigger(appState: AppState) -> some View {
        modifier(LocalizedRefreshModifier(appState: appState))
    }

    func localizedRefreshTrigger() -> some View {
        modifier(LocalizedRefreshFallbackModifier())
    }
}
