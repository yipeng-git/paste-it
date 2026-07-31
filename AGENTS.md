# Agent notes — Paste It (macOS)

## Verify UI / behavior with a signed install

When a change needs real-app verification (gestures, paste, Accessibility, panels, selection, etc.), **do not only `swift build` / `run-app.sh`**. Package a signed arm64 build, install it to `/Applications`, and launch it yourself.

```sh
./scripts/package-release.sh --variant arm64

# Quit existing app if running, then:
rm -rf "/Applications/Paste It.app"
cp -R "dist/arm64/Paste It.app" "/Applications/Paste It.app"
xattr -dr com.apple.quarantine "/Applications/Paste It.app" 2>/dev/null || true
open "/Applications/Paste It.app"
```

Prerequisites and notarization details: [`docs/mac-packaging.md`](docs/mac-packaging.md).
