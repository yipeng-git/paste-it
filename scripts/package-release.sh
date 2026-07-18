#!/usr/bin/env bash
# Build, Developer ID–sign, notarize, and package Paste It! as DMGs.
# Produces two artifacts:
#   PasteIt-{ver}-arm64.dmg      — Apple Silicon only
#   PasteIt-{ver}-universal.dmg  — arm64 + x86_64 (Intel + Apple Silicon)
# Prerequisites: docs/mac-packaging.md
#
# PasteIt.entitlements is intentionally an empty dict:
#   - Direct distribution (not Mac App Store) → no App Sandbox entitlements needed.
#   - Hardened Runtime is enabled via `codesign --options runtime` below, not via entitlements.
#   - Sparkle 2 works without sandbox XPC entitlements when the app is not sandboxed.
# NOTE: do not add XML comments inside PasteIt.entitlements itself — the kernel's
# AMFI entitlements parser (AMFIUnserializeXML) rejects <!-- --> comments with a
# syntax error, even though it's valid plist XML that Xcode/plutil accept fine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_NOTARIZE=0
SKIP_DMG=0
CONFIGURATION=release
# both | arm64 | universal
VARIANT=both

usage() {
  cat <<'EOF'
Usage: package-release.sh [options]

  --skip-notarize   Sign only (no notarytool / stapler)
  --skip-dmg        Stop after signed (and optionally notarized) .app
  --variant NAME    both (default) | arm64 | universal
  -h, --help        Show this help

Env:
  PASTEIT_CODESIGN_IDENTITY   Full "Developer ID Application: …" string
  PASTEIT_NOTARY_PROFILE      notarytool keychain profile (default: paste-it-notary)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-dmg) SKIP_DMG=1; shift ;;
    --variant)
      VARIANT="${2:-}"
      [[ "$VARIANT" == "both" || "$VARIANT" == "arm64" || "$VARIANT" == "universal" ]] \
        || { echo "Invalid --variant: $VARIANT (use both|arm64|universal)" >&2; exit 1; }
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

ENTITLEMENTS="$ROOT/PasteIt.entitlements"
DIST="$ROOT/dist"
APP_NAME="Paste It.app"
ICON="$ROOT/Resources/AppIcon.icns"
ASSETS_CAR="$ROOT/Resources/Assets.car"
NOTARY_PROFILE="${PASTEIT_NOTARY_PROFILE:-paste-it-notary}"

plist_version() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$ROOT/Info.plist"
}

SHORT_VERSION="$(plist_version CFBundleShortVersionString)"
BUILD_VERSION="$(plist_version CFBundleVersion)"

resolve_identity() {
  if [[ -n "${PASTEIT_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$PASTEIT_CODESIGN_IDENTITY"
    return 0
  fi
  local found
  found="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1 || true)"
  if [[ -z "$found" ]]; then
    echo "No Developer ID Application identity found." >&2
    echo "Create one in Apple Developer → Certificates, then either:" >&2
    echo "  export PASTEIT_CODESIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\"" >&2
    echo "or see docs/mac-packaging.md" >&2
    echo "" >&2
    echo "Current identities:" >&2
    security find-identity -v -p codesigning >&2 || true
    return 1
  fi
  printf '%s\n' "$found"
  return 0
}

IDENTITY="$(resolve_identity)" || exit 1
echo "Signing identity: $IDENTITY"
echo "Version: $SHORT_VERSION ($BUILD_VERSION)"
echo "Variant: $VARIANT"

# Hardening build flags:
#   -file-prefix-map  strips the local checkout path (username!) from paths
#                     embedded in fatalError/assert messages and debug info.
#   -dead_strip       drops unreachable code from the final binary.
REPO_ROOT="$ROOT"
BUILD_FLAGS=(
  -Xswiftc -file-prefix-map -Xswiftc "$REPO_ROOT=/pasteit"
  -Xlinker -dead_strip
)

bin_path_for_arch() {
  local arch="$1"
  swift build -c "$CONFIGURATION" --arch "$arch" "${BUILD_FLAGS[@]}" --show-bin-path
}

build_arch() {
  local arch="$1"
  echo "==> swift build -c $CONFIGURATION --arch $arch (hardened)"
  swift build -c "$CONFIGURATION" --arch "$arch" "${BUILD_FLAGS[@]}"
  local bin_dir
  bin_dir="$(bin_path_for_arch "$arch")"
  [[ -x "$bin_dir/PasteIt" ]] || { echo "Missing binary: $bin_dir/PasteIt" >&2; exit 1; }
  [[ -d "$bin_dir/Sparkle.framework" ]] \
    || { echo "Missing Sparkle.framework next to binary (SPM copy step failed?)" >&2; exit 1; }
}

sign() {
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"
}

sign_app_bundle() {
  local app="$1"
  local sparkle="$app/Contents/Frameworks/Sparkle.framework"
  local sparkle_b="$sparkle/Versions/B"

  echo "==> Sign Sparkle (inside-out, no --deep) — $(basename "$(dirname "$app")")"
  if [[ -d "$sparkle_b/XPCServices/Installer.xpc" ]]; then
    sign "$sparkle_b/XPCServices/Installer.xpc"
  fi
  if [[ -d "$sparkle_b/XPCServices/Downloader.xpc" ]]; then
    sign --preserve-metadata=entitlements "$sparkle_b/XPCServices/Downloader.xpc"
  fi
  if [[ -f "$sparkle_b/Autoupdate" ]]; then
    sign "$sparkle_b/Autoupdate"
  fi
  if [[ -d "$sparkle_b/Updater.app" ]]; then
    sign "$sparkle_b/Updater.app"
  fi
  sign "$sparkle"

  echo "==> Sign app — $(basename "$(dirname "$app")")"
  sign --entitlements "$ENTITLEMENTS" "$app"

  echo "==> Verify signature"
  codesign --verify --deep --strict --verbose=2 "$app"
  codesign -dv --verbose=4 "$app" 2>&1 | grep -E 'Authority|Runtime|Identifier|Format' || true
}

notarize_app() {
  local app="$1"
  local label="$2"
  if [[ "$SKIP_NOTARIZE" -ne 0 ]]; then
    echo "==> Skipping notarization (--skip-notarize) — $label"
    return 0
  fi
  local zip="$DIST/PasteIt-${SHORT_VERSION}-${label}-notarize.zip"
  echo "==> Zip for notarization → $zip"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"

  echo "==> notarytool submit (profile: $NOTARY_PROFILE) — $label"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> stapler staple — $label"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  rm -f "$zip"
}

create_dmg() {
  local app="$1"
  local dmg_path="$2"
  local volname="Paste It"
  local stage="$DIST/dmg-stage-$(basename "$dmg_path" .dmg)"
  local dmg_rw="$DIST/.pasteit-rw-$(basename "$dmg_path" .dmg).dmg"
  local dmg_background="$ROOT/Resources/dmg-background.png"
  local mount_dir="/Volumes/$volname"

  echo "==> Create DMG → $dmg_path"
  rm -rf "$stage" "$dmg_path" "$dmg_rw"
  mkdir -p "$stage"
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"
  if [[ -f "$dmg_background" ]]; then
    mkdir -p "$stage/.background"
    cp "$dmg_background" "$stage/.background/background.png"
  fi

  local stage_mb
  stage_mb="$(du -sm "$stage" | cut -f1)"
  hdiutil create \
    -volname "$volname" \
    -srcfolder "$stage" \
    -fs HFS+ \
    -format UDRW \
    -size "$((stage_mb + 40))m" \
    -ov \
    "$dmg_rw"

  if [[ -d "$mount_dir" ]]; then
    hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
  fi
  hdiutil attach "$dmg_rw" -noverify -noautoopen -mountpoint "$mount_dir"

  echo "==> Style DMG window (Finder)"
  osascript <<OSA || echo "  (Finder styling skipped/failed — DMG contents are still fine, just unstyled)"
tell application "Finder"
  tell disk "$volname"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set the bounds of container window to {400, 100, 1060, 528}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set text size of theViewOptions to 12
    try
      set background picture of theViewOptions to POSIX file "$mount_dir/.background/background.png"
    end try
    set position of item "$APP_NAME" of container window to {180, 180}
    set position of item "Applications" of container window to {480, 180}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
OSA

  sync
  hdiutil detach "$mount_dir" -force

  echo "==> Compress DMG"
  rm -f "$dmg_path"
  hdiutil convert "$dmg_rw" -format UDZO -imagekey zlib-level=9 -o "$dmg_path"
  rm -f "$dmg_rw"
  rm -rf "$stage"

  sign "$dmg_path"
}

# Assemble .app at $app_dir/$APP_NAME from a single binary path (may already be lipo'd).
# sparkle_src: directory containing Sparkle.framework (and optional resource bundle).
assemble_app() {
  local app_dir="$1"
  local binary="$2"
  local sparkle_src="$3"
  local label="$4"
  local app="$app_dir/$APP_NAME"

  echo "==> Assemble $app ($label)"
  rm -rf "$app_dir"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
  cp "$binary" "$app/Contents/MacOS/PasteIt"
  cp "$ROOT/Info.plist" "$app/Contents/Info.plist"
  if [[ -f "$ICON" ]]; then
    cp "$ICON" "$app/Contents/Resources/AppIcon.icns"
  fi
  if [[ -f "$ASSETS_CAR" ]]; then
    cp "$ASSETS_CAR" "$app/Contents/Resources/Assets.car"
  fi
  cp -R "$sparkle_src/Sparkle.framework" "$app/Contents/Frameworks/"
  if [[ -d "$sparkle_src/PasteIt_PasteIt.bundle" ]]; then
    cp -R "$sparkle_src/PasteIt_PasteIt.bundle" "$app/Contents/Resources/"
  fi

  install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/PasteIt" 2>/dev/null || true

  local dsym="$DIST/PasteIt-${SHORT_VERSION}-${label}.dSYM"
  echo "==> dsymutil → $dsym"
  dsymutil "$app/Contents/MacOS/PasteIt" -o "$dsym"
  echo "==> strip binary ($label)"
  strip -rSTx "$app/Contents/MacOS/PasteIt"

  echo "  arches: $(lipo -archs "$app/Contents/MacOS/PasteIt")"
}

package_variant() {
  local label="$1"   # arm64 | universal
  local binary="$2"
  local sparkle_src="$3"
  local app_dir="$DIST/$label"
  local app="$app_dir/$APP_NAME"
  local dmg="$DIST/PasteIt-${SHORT_VERSION}-${label}.dmg"

  assemble_app "$app_dir" "$binary" "$sparkle_src" "$label"
  sign_app_bundle "$app"
  notarize_app "$app" "$label"

  if [[ "$SKIP_DMG" -eq 1 ]]; then
    echo "Done (no DMG): $app"
    return 0
  fi
  create_dmg "$app" "$dmg"
}

# --- build ---
rm -rf "$DIST"
mkdir -p "$DIST"

NEED_ARM64=0
NEED_X86=0
[[ "$VARIANT" == "both" || "$VARIANT" == "arm64" || "$VARIANT" == "universal" ]] && NEED_ARM64=1
[[ "$VARIANT" == "both" || "$VARIANT" == "universal" ]] && NEED_X86=1

if [[ "$NEED_ARM64" -eq 1 ]]; then
  build_arch arm64
fi
if [[ "$NEED_X86" -eq 1 ]]; then
  build_arch x86_64
fi

ARM64_BIN_DIR="$(bin_path_for_arch arm64)"
X86_BIN_DIR=""
if [[ "$NEED_X86" -eq 1 ]]; then
  X86_BIN_DIR="$(bin_path_for_arch x86_64)"
fi

UNIVERSAL_BIN=""
if [[ "$NEED_X86" -eq 1 ]]; then
  UNIVERSAL_BIN="$DIST/PasteIt-universal-bin"
  echo "==> lipo → $UNIVERSAL_BIN"
  lipo -create \
    "$ARM64_BIN_DIR/PasteIt" \
    "$X86_BIN_DIR/PasteIt" \
    -output "$UNIVERSAL_BIN"
  chmod +x "$UNIVERSAL_BIN"
fi

if [[ "$VARIANT" == "both" || "$VARIANT" == "arm64" ]]; then
  package_variant arm64 "$ARM64_BIN_DIR/PasteIt" "$ARM64_BIN_DIR"
fi
if [[ "$VARIANT" == "both" || "$VARIANT" == "universal" ]]; then
  # Sparkle.framework from either build dir is already fat (macos-arm64_x86_64).
  package_variant universal "$UNIVERSAL_BIN" "$ARM64_BIN_DIR"
fi

echo ""
echo "Release artifacts:"
if [[ "$VARIANT" == "both" || "$VARIANT" == "arm64" ]]; then
  echo "  App (arm64):     $DIST/arm64/$APP_NAME"
  [[ "$SKIP_DMG" -eq 0 ]] && echo "  DMG (arm64):     $DIST/PasteIt-${SHORT_VERSION}-arm64.dmg"
fi
if [[ "$VARIANT" == "both" || "$VARIANT" == "universal" ]]; then
  echo "  App (universal): $DIST/universal/$APP_NAME"
  [[ "$SKIP_DMG" -eq 0 ]] && echo "  DMG (universal): $DIST/PasteIt-${SHORT_VERSION}-universal.dmg"
fi
echo ""
echo "Next: copy DMGs to updates/, run generate-appcast.sh, upload GitHub Release mac-v${SHORT_VERSION}."
echo "See docs/mac-packaging.md and docs/mac-updates.md"
