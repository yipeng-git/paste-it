import AppKit
import PasteItCore
import SwiftUI

/// Toolbar overflow control, styled to match the search field glass chrome.
/// Menu contents are owned by `AppRuntime.makeAppMenu()` so status-bar-adjacent
/// AppKit menus stay in sync.
struct AppMenuButton: View {
    var onWillOpen: (() -> Void)? = nil

    private var moreLabel: String { L10n.tr("menu.more", default: "More") }

    var body: some View {
        AppMenuHost(onWillOpen: onWillOpen, accessibilityLabel: moreLabel)
            .frame(width: 38, height: 28)
            .pasteItControlGlass()
            .help(moreLabel)
            .accessibilityLabel(moreLabel)
    }
}

private struct AppMenuHost: NSViewRepresentable {
    var onWillOpen: (() -> Void)?
    var accessibilityLabel: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = ""
        button.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: accessibilityLabel
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

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.onWillOpen = onWillOpen
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onWillOpen: onWillOpen)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onWillOpen: (() -> Void)?

        init(onWillOpen: (() -> Void)?) {
            self.onWillOpen = onWillOpen
        }

        @objc func showMenu(_ sender: NSButton) {
            onWillOpen?()
            AppRuntime.shared.popUpAppMenu(relativeTo: sender)
        }
    }
}
