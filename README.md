# Paste It

**English** | [中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

A local clipboard manager for macOS — visual timeline, searchable history (including text inside screenshots), and a native feel that stays out of your way.

**Website:** [paste-it.app](https://paste-it.app)

![Paste It timeline panel](docs/screenshots/paste-it-history-panel.png)

## Features

- Visual timeline of everything you copy
- Search text — including words inside screenshots and images
- Preview a clip, edit it, then paste
- Pin important items (and keep them in folders)
- Paste Stack for pasting several clips in order

## Install

1. Download the latest build from [paste-it.app](https://paste-it.app) or [GitHub Releases](https://github.com/yipeng-git/paste-it/releases/latest).
2. Open the `.dmg` (or unzip) and drag **Paste It** into **Applications**.
3. Launch it from Applications. It lives in the menu bar.
4. For one-key paste into other apps, allow **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility).

macOS 14 or later. Official builds update themselves in the background.

## Usage

1. Copy as usual — Paste It keeps a local history.
2. Press **⇧⌘V** (or click the menu bar icon) to open the timeline.
3. Type to search, or filter by type. Use **⌘1…9** for a quick pick, or select a card and press **Return** to paste.
4. Press **Space** to preview above the timeline. Click the text to edit; for images you can review OCR, for links you get a page preview.
5. Pin clips you want to keep, or put them in a custom folder (up to three folders).

### More shortcuts

| Shortcut | Action |
|----------|--------|
| **⇧⌘V** | Open / close timeline |
| **⌘1…9** | Stage that card and close |
| **Return** | Paste selection (needs Accessibility) |
| **⇧Return** | Paste as plain text |
| **Space** | Preview |
| **⌘E** | Edit selected clip |
| **⇧⌘C** | Open Paste Stack |
| **⌥⌘V** | Paste next from Stack |
| **⌃⌘V** | Paste current clipboard as plain text once |
| **⇧⌘T** | Pause / resume capture (from the menu) |

**Paste Stack:** press **⇧⌘C**, copy several things into the queue, then **⌥⌘V** (or **⌘V** while the stack is open) to paste them one by one. Direction (oldest / newest first) is in Settings → Stack.

**Multi-select:** **⌘**-click several cards, then **Return** to paste in order.

Selecting a clip puts it on the system clipboard without Accessibility. Auto-paste (**Return**, Stack, **⌃⌘V**) needs Accessibility.

## Privacy

History stays on this Mac — no account, no cloud sync. Password managers and other protected pasteboard types are skipped by default. You can pause capture, ignore apps, and limit how long history is kept in Settings.

Optional anonymous analytics (on in official builds) never includes clipboard contents, OCR, paths, or search queries. Turn it off anytime in **Settings → Privacy**. Details: [`docs/analytics.md`](docs/analytics.md).

## For agents (optional)

Paste It can expose a local [MCP](https://modelcontextprotocol.io) server so agents can read and search history. **Off by default** — enable **MCP** from the menu bar while the app is running (`http://127.0.0.1:17321/mcp`). Setup and tools: [`docs/mcp.md`](docs/mcp.md).

## Build from source

For contributors:

```sh
swift run PasteIt
# or
./scripts/run-app.sh
```

Requires Xcode / Swift 6.2. Packaging and signing: [`docs/mac-packaging.md`](docs/mac-packaging.md). Updates plumbing: [`docs/mac-updates.md`](docs/mac-updates.md).

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — free for personal, educational, research, hobby, and other noncommercial use. **Commercial use requires a separate license** from the copyright holder.

Versions published under MIT before this change remain available under MIT for those releases only.
