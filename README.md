# Paste It

Paste It is a local-first macOS clipboard manager. It is written with SwiftUI, AppKit, and SwiftData. Clipboard history always stays on this Mac — there is no account, trial, or cloud sync.

## Features

- Background clipboard history via `NSPasteboard.general.changeCount` polling.
- Text, rich text, HTML, images, file URLs, and links.
- Local SwiftData metadata plus file-backed binary storage under Application Support.
- OCR indexing for copied images and screenshots using Vision.
- Spotlight-style floating `NSPanel` opened with `Shift + Command + V`.
- Menu bar app, search, type filters, source app metadata, visual cards, and preview pane.
- Direct clipboard staging, paste as plain text, multi-item text copy, and Quick Copy with `Command + 1...9`.
- Pinboards with drag-and-drop pinning and permanent retention.
- Paste Stack with `Shift + Command + C` collection, ordering control, and sequential paste preparation.
- Privacy controls for paused capture, ignored apps, ignored pasteboard types, history retention, and storage pruning.
- In-app updates via Sparkle.

## Requirements

- macOS 14+
- Xcode / Swift 6.2 toolchain

## Run

```sh
swift run PasteIt
```

To package a minimal `.app` (embeds Sparkle for update checks):

```sh
./scripts/run-app.sh
```

Open this folder in Xcode to run and debug it as a Swift Package.

## Updates

Auto-updates use Sparkle. The feed URL is `SUFeedURL` in [`Info.plist`](Info.plist) (GitHub Pages). See [`docs/mac-updates.md`](docs/mac-updates.md). Signed release builds use [`scripts/package-release.sh`](scripts/package-release.sh) — setup in [`docs/mac-packaging.md`](docs/mac-packaging.md).

## Clipboard staging

Selecting a clip only writes it to the system pasteboard. Paste It does not synthesize `Command + V` for normal timeline staging and does not require Accessibility for that path. Paste Stack’s “Paste Next” optionally synthesizes `Command + V` and needs Accessibility permission.

Global shortcuts use `NSEvent` monitors (`Shift+Cmd+V` timeline, `Shift+Cmd+C` Paste Stack, `Cmd+1…9` Quick Copy).

## MCP

Optional local MCP server (Stateless HTTP) for agents: read history + ephemeral timeline screenshots. Off by default; enable from the menu bar **MCP** item. See [`docs/mcp.md`](docs/mcp.md).

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — free for personal, educational, research, hobby, and other noncommercial use. **Commercial use requires a separate license** from the copyright holder.

Versions published under MIT before this change remain available under MIT for those releases only.
