# Agent notes — Paste It (macOS)

## Verify UI / behavior with a signed install

When a change needs real-app verification (gestures, paste, Accessibility, panels, selection, etc.), **do not only `swift build` / `run-app.sh`**. Never install an unsigned / ad-hoc / `.build` debug binary to `/Applications`.

Package a **Developer ID–signed** arm64 build, install it to `/Applications`, and launch it yourself. Notarization is **not** required for local verify — `--skip-notarize` is fine.

```sh
./scripts/package-release.sh --variant arm64 --skip-notarize --skip-dmg

# Quit existing app if running, then:
rm -rf "/Applications/Paste It.app"
cp -R "dist/arm64/Paste It.app" "/Applications/Paste It.app"
xattr -dr com.apple.quarantine "/Applications/Paste It.app" 2>/dev/null || true
open "/Applications/Paste It.app"
```

Confirm before handing off: `codesign -dv "/Applications/Paste It.app" 2>&1 | grep Authority` shows `Developer ID Application: …`.

Prerequisites and notarization details: [`docs/mac-packaging.md`](docs/mac-packaging.md).
