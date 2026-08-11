# Paste It

**English** | [中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

A local-only macOS clipboard manager — native SwiftUI, Liquid Glass, and MCP for agents.

**Website:** [paste-it.app](https://paste-it.app)

![Paste It timeline panel](docs/screenshots/paste-it-history-panel.png)

- **Local only** — No account, no cloud sync. Clipboard history stays on this Mac.
- **Native SwiftUI** — AppKit floating panel with a SwiftUI timeline. **Liquid Glass on macOS 26+** (material fallback on earlier versions).
- **AI-native** — Optional local **MCP** so agents can read history, search (including OCR text), and render ephemeral timeline screenshots.
- **Searchable clipboard** — Vision OCR indexes copied images and screenshots, alongside text, rich text, HTML, files, and links.

![Search clipboard history including OCR](docs/screenshots/paste-it-ocr-search.png)

Search finds text inside screenshots and images — not only plain clipboard text.

## Features

- Floating timeline with **Shift + Command + V** — browse visual cards and a preview pane.
- Pinboards with drag-and-drop pinning and permanent retention.
- Paste Stack (**Shift + Command + C**) — collect, reorder, and prepare sequential pastes.
- **Paste without formatting** — **Control + Command + V** strips the current clipboard to plain text and pastes (Accessibility required to auto-paste).
- Quick Copy with **Command + 1…9**, and multi-item text copy.
- Privacy controls: pause capture, ignore apps or pasteboard types, retention, and storage pruning.
- Optional anonymous usage analytics (PostHog) — never clipboard contents; see [`docs/analytics.md`](docs/analytics.md) and dashboard guide [`docs/analytics-dashboard.md`](docs/analytics-dashboard.md). Toggle in Settings → Privacy.
- In-app updates via Sparkle.

Selecting a clip stages it on the system pasteboard (no Accessibility needed). Paste Stack’s “Paste Next” optionally synthesizes **Command + V** and requires Accessibility.

## Privacy & analytics

Clipboard history is **local-only**. Optional PostHog analytics (on by default in official builds) reports anonymous product events such as panel open/close, staging, onboarding, and update funnel — **never** clipboard text, OCR, paths, or search queries. Full event list: [`docs/analytics.md`](docs/analytics.md). How to build the product dashboard: [`docs/analytics-dashboard.md`](docs/analytics-dashboard.md). Disable anytime in **Settings → Privacy**.

## MCP for agents

Optional local [Model Context Protocol](https://modelcontextprotocol.io) server — **off by default**. Enable from the menu bar **MCP** item while Paste It is running.

- URL: `http://127.0.0.1:17321/mcp` (loopback only, Stateless HTTP)
- Read-only history: list, get, search (source app, OCR, and the same query language as the app)
- Ephemeral timeline screenshots from card payloads (does not write main history)

Full tools, curl examples, and client setup: [`docs/mcp.md`](docs/mcp.md).

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

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — free for personal, educational, research, hobby, and other noncommercial use. **Commercial use requires a separate license** from the copyright holder.

Versions published under MIT before this change remain available under MIT for those releases only.
