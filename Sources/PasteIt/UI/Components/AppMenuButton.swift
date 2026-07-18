import AppKit
import SwiftUI

/// Toolbar overflow control, styled to match the search field glass chrome.
/// Menu contents are owned by `AppRuntime.makeAppMenu()` so status-bar-adjacent
/// AppKit menus stay in sync.
struct AppMenuButton: View {
    var body: some View {
        AppMenuHost()
            .frame(width: 38, height: 28)
            .pasteItControlGlass()
            .help("More")
            .accessibilityLabel("More")
    }
}

private struct AppMenuHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = ""
        button.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: "More"
        )
        button.imagePosition = .imageOnly
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setButtonType(.momentaryChange)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        @objc func showMenu(_ sender: NSButton) {
            AppRuntime.shared.popUpAppMenu(relativeTo: sender)
        }
    }
}
