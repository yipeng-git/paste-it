#!/usr/bin/env bash
# Generate Sparkle appcast.xml from DMGs in updates/.
# Sparkle tools are pinned + auto-downloaded into .tools/sparkle/
# (gitignored) so the toolchain survives reboots, unlike /tmp.
# Private EdDSA key must be in the Keychain (from generate_keys).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATES="${UPDATES_DIR:-$ROOT/updates}"
DOCS_APPCAST="$ROOT/docs/appcast.xml"

# Keep in sync with the Sparkle version in Package.resolved.
SPARKLE_TOOLS_VERSION="${SPARKLE_TOOLS_VERSION:-2.9.4}"
TOOLS_DIR="$ROOT/.tools/sparkle"

ensure_sparkle_tools() {
  if [[ -x "$TOOLS_DIR/bin/generate_appcast" ]]; then
    return 0
  fi
  echo "==> Downloading Sparkle $SPARKLE_TOOLS_VERSION tools → $TOOLS_DIR"
  local url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_TOOLS_VERSION}/Sparkle-${SPARKLE_TOOLS_VERSION}.tar.xz"
  local tmp
  tmp="$(mktemp -d)"
  curl -fL --retry 3 -o "$tmp/sparkle.tar.xz" "$url"
  mkdir -p "$TOOLS_DIR"
  tar -xJf "$tmp/sparkle.tar.xz" -C "$TOOLS_DIR"
  rm -rf "$tmp"
  [[ -x "$TOOLS_DIR/bin/generate_appcast" ]] || {
    echo "generate_appcast missing after extract — check $TOOLS_DIR" >&2
    exit 1
  }
}

GENERATE_APPCAST=""
if [[ -n "${SPARKLE_BIN:-}" && -x "$SPARKLE_BIN/generate_appcast" ]]; then
  GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
else
  ensure_sparkle_tools
  GENERATE_APPCAST="$TOOLS_DIR/bin/generate_appcast"
fi

if [[ ! -d "$UPDATES" ]]; then
  echo "Create $UPDATES and place PasteIt-*.dmg files there first." >&2
  exit 1
fi

shopt -s nullglob
DMGS=("$UPDATES"/*.dmg "$UPDATES"/*.zip)
if [[ ${#DMGS[@]} -eq 0 ]]; then
  echo "No .dmg/.zip in $UPDATES" >&2
  exit 1
fi

echo "Using $GENERATE_APPCAST"
echo "Scanning $UPDATES"
"$GENERATE_APPCAST" "$UPDATES"

if [[ -f "$UPDATES/appcast.xml" ]]; then
  echo "Generated $UPDATES/appcast.xml"
  echo "Next (or just run scripts/release.sh which does all of this):"
  echo "  1. Rewrite enclosure urls to GitHub release download URLs if needed"
  echo "  2. cp \"$UPDATES/appcast.xml\" \"$DOCS_APPCAST\""
  echo "  3. Upload DMGs to a GitHub Release mac-vX.Y.Z on this same repository"
  echo "  4. Push so GitHub Pages serves docs/appcast.xml (…/paste-it/appcast.xml)"
else
  echo "Expected appcast at $UPDATES/appcast.xml — check generate_appcast output." >&2
  exit 1
fi
