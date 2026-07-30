#!/usr/bin/env bash
# Build the SPM executable into a minimal .app (embeds Sparkle.framework for UpdateChecker).
# Debug only — release packaging is scripts/package-release.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/posthog-secrets.sh
source "$ROOT/scripts/lib/posthog-secrets.sh"

swift build -c debug
BIN_DIR="$(swift build -c debug --show-bin-path)"
BIN="$BIN_DIR/PasteIt"
APP="$ROOT/.build/PasteIt.app"
ICON="$ROOT/Resources/AppIcon.icns"
ASSETS_CAR="$ROOT/Resources/Assets.car"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/PasteIt"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
inject_posthog_token "$APP/Contents/Info.plist"
if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$ASSETS_CAR" ]]; then
  cp "$ASSETS_CAR" "$APP/Contents/Resources/Assets.car"
fi
if [[ -d "$BIN_DIR/Sparkle.framework" ]]; then
  rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
  cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
  # SPM links @rpath/Sparkle.framework; point rpath at Contents/Frameworks.
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/PasteIt" 2>/dev/null || true
fi
if [[ -d "$BIN_DIR/PasteIt_PasteIt.bundle" ]]; then
  cp -R "$BIN_DIR/PasteIt_PasteIt.bundle" "$APP/Contents/Resources/"
fi

# install_name_tool invalidates the ad-hoc SPM signature; re-sign so Gatekeeper won't SIGKILL.
codesign --force --deep --sign - "$APP" >/dev/null

echo "Built $APP"
open "$APP"
