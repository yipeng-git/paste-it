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
3. Click Search (or **⌘F**) to search, or filter by type. Select a card, then use **Return**, double-click, or **⌘1…9** for your primary action (see below).
4. Press **Space** to preview above the timeline. Click the text to edit; for images you can review OCR, for links you get a page preview.
5. Pin clips you want to keep, or put them in a custom folder (up to three folders).

### More shortcuts

| Shortcut | Action |
|----------|--------|
| **⇧⌘V** | Open / close timeline |
| **⌘1…9** | Primary action on that card |
| **Return** | Primary action on selection |
| **⇧Return** | Paste as plain text |
| **Space** | Preview |
| **⌘E** | Edit selected clip |
| **⇧⌘C** | Open Paste Stack |
| **⌃⌘V** | Paste current clipboard as plain text once |
| **⇧⌘T** | Pause / resume capture (from the menu) |

**Paste Stack:** press **⇧⌘C**, copy several things into the queue, then **⌘V** in the target app to paste them one by one. Direction (oldest / newest first) is in Settings → Stack.

**Multi-select:** **⌘**-click several cards, then **Return** in Direct Paste mode to paste in displayed order. **⇧Return** pastes them as plain text in any mode.

Single-click selects without changing the clipboard. **⌘C** or the Copy button copies one clip and keeps the panel open. **Settings → General → Timeline primary action** offers **Direct Paste** and **Copy Only**: double-click, **Return**, and **⌘1…9** all use that action. Direct Paste is the default for both new and existing installs. An explicitly selected Copy Only preference is preserved. **⇧Return** always requests plain-text paste.

Direct paste needs Accessibility. Without it, a single clip is copied and a recovery dialog explains how to return to your app and press **⌘V**. Failed writes keep your selection and show Retry. **⌘C** with multiple clips asks you to select one, rather than silently copying only the first.

**Removal:** Remove from History leaves clips saved in Pinned or folders there. Unpin and Remove from Folder affect that location only. **Menu → Undo Removal / ⌘Z** restores recent removals for **30 seconds**, up to 20 actions in the current app session. Attachments are protected while undo is available. **Delete Everywhere** is confirmed and cannot be undone. Bulk cleanup and shorter retention show the affected count before applying; saved clips are explicitly included or excluded. Confirming bulk cleanup ends removal undo.

Ordinary removal shows a **3-second toast with Undo**; hovering pauses its dismissal, then the remaining display time resumes when the pointer leaves. The toast floats centered 12 points above the panel without changing its layout or taking keyboard focus. It uses native Liquid Glass on macOS 26+ and standard material on older macOS versions; short messages fit a capsule and long messages wrap into a rounded rectangle. Undo highlights on hover and responds visually when pressed; the toast adds no extra window shadow. After it disappears, the menu and **⌘Z** still work within the original 30-second undo window. Folder actions name their destination, such as **Remove from “Work”**. **Delete Everywhere…** opens the permanent-deletion confirmation.

Settings use an always-visible native sidebar without a collapse button, opening on **General**. Like System Settings, the sidebar extends through the titlebar and uses compact rows with colored icons; version information lives under **About**. General only shows an Accessibility prompt when Direct Paste is selected and permission is missing; full permission status remains under **Privacy**. **Clipboard** contains capture, retention, and history limits; clipboard polling is under **Advanced**. Permissions are also available under **Privacy**, and cleanup stays under **Storage**. The sidebar adopts native Liquid Glass on macOS 26, with standard system styling on earlier releases. Window size and position are remembered.

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
