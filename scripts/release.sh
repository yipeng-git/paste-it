#!/usr/bin/env bash
# One-command Mac release: version bump → package (sign/notarize/DMG) →
# appcast → GitHub Release (public repo) → docs/appcast.xml → commit + tag.
#
# Usage:
#   ./scripts/release.sh 0.2.0                # full release
#   ./scripts/release.sh 0.2.0 --dry-run      # everything local; no gh release,
#                                             # no commit/tag/push
#   ./scripts/release.sh 0.2.0 --skip-package # reuse dist/ DMGs (resume a run)
#   ./scripts/release.sh 0.2.0 --no-push      # commit + tag locally, push manually
#
# Ships two DMGs per version:
#   PasteIt-{ver}-arm64.dmg
#   PasteIt-{ver}-universal.dmg
#
# Docs: docs/mac-updates.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
UPDATES="$ROOT/updates"
DIST="$ROOT/dist"
DOCS_APPCAST="$ROOT/docs/appcast.xml"
INFO_PLIST="$ROOT/Info.plist"

# DMGs ship as GitHub Releases on this same repository (not a separate CDN repo).
if [[ -n "${PASTEIT_RELEASE_REPO:-}" ]]; then
  RELEASE_REPO="$PASTEIT_RELEASE_REPO"
elif remote_url="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"; then
  RELEASE_REPO="$(printf '%s\n' "$remote_url" | sed -E 's#(git@|https://)github\.com[:/]##; s#\.git$##')"
else
  RELEASE_REPO="yipeng-git/paste-it"
fi
DOWNLOAD_BASE="https://github.com/$RELEASE_REPO/releases/download"
NOTARY_PROFILE="${PASTEIT_NOTARY_PROFILE:-paste-it-notary}"
MINIMUM_SYSTEM_VERSION="14.0"
FEED_OWNER="${RELEASE_REPO%%/*}"
FEED_NAME="${RELEASE_REPO##*/}"
FEED_URL="https://${FEED_OWNER}.github.io/${FEED_NAME}/appcast.xml"

VERSION=""
DRY_RUN=0
SKIP_PACKAGE=0
NO_PUSH=0

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,16p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --skip-package) SKIP_PACKAGE=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *)
      [[ -z "$VERSION" ]] || die "unexpected argument: $1"
      VERSION="$1"; shift ;;
  esac
done

[[ -n "$VERSION" ]] || { usage >&2; die "version required, e.g. ./scripts/release.sh 0.2.0"; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be semver X.Y.Z, got: $VERSION"

TAG="mac-v$VERSION"
DMG_ARM64="PasteIt-$VERSION-arm64.dmg"
DMG_UNIVERSAL="PasteIt-$VERSION-universal.dmg"

# ---------------------------------------------------------------- preflight
log "Preflight"

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"

if [[ "$SKIP_PACKAGE" -eq 1 ]]; then
  # Resuming: dist/ already holds packaged builds for this version, so the
  # plist must already match — bumping again would desync plist vs DMG.
  [[ "$CURRENT_VERSION" == "$VERSION" ]] \
    || die "--skip-package requires Info.plist version ($CURRENT_VERSION) == $VERSION"
  NEW_BUILD="$CURRENT_BUILD"
else
  NEW_BUILD=$((CURRENT_BUILD + 1))
  # New version must sort >= current (sort -V puts the larger one last).
  HIGHEST="$(printf '%s\n%s\n' "$CURRENT_VERSION" "$VERSION" | sort -V | tail -1)"
  [[ "$HIGHEST" == "$VERSION" ]] || die "version $VERSION is older than current $CURRENT_VERSION"
fi

git -C "$ROOT" rev-parse --verify -q "refs/tags/$TAG" >/dev/null \
  && die "git tag $TAG already exists"

if [[ "$DRY_RUN" -eq 0 ]]; then
  # A resumed run legitimately carries the version bump from the failed run.
  if [[ "$SKIP_PACKAGE" -eq 0 ]]; then
    DIRTY="$(git -C "$ROOT" status --porcelain)"
    [[ -z "$DIRTY" ]] || die "working tree is dirty — commit or stash first:
$DIRTY"
  fi

  command -v gh >/dev/null || die "gh CLI not installed"
  gh auth status >/dev/null 2>&1 || die "gh not logged in (gh auth login)"
  gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1 \
    && die "release $TAG already exists on $RELEASE_REPO"

  security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || die "no Developer ID Application identity in Keychain"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notarytool profile '$NOTARY_PROFILE' not usable (store-credentials?)"
else
  log "(dry-run: skipping git-clean / gh / release-exists checks)"
fi

echo "  version: $CURRENT_VERSION ($CURRENT_BUILD) → $VERSION ($NEW_BUILD)"
echo "  tag:     $TAG"
echo "  repo:    $RELEASE_REPO"
echo "  dmgs:    $DMG_ARM64 + $DMG_UNIVERSAL"

# ------------------------------------------------------ version bump + package
if [[ "$SKIP_PACKAGE" -eq 0 ]]; then
  log "Bump Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

  log "Package (build / sign / notarize / dual DMG)"
  "$SCRIPTS/package-release.sh"
else
  log "Skipping bump + package (--skip-package: reusing dist/ for $VERSION build $NEW_BUILD)"
fi

DMG_ARM64_PATH="$DIST/$DMG_ARM64"
DMG_UNIVERSAL_PATH="$DIST/$DMG_UNIVERSAL"
[[ -f "$DMG_ARM64_PATH" ]] || die "missing DMG: $DMG_ARM64_PATH (did package-release.sh succeed?)"
[[ -f "$DMG_UNIVERSAL_PATH" ]] || die "missing DMG: $DMG_UNIVERSAL_PATH (did package-release.sh succeed?)"

# ------------------------------------------------------------------ appcast
# Sparkle generate_appcast rejects two archives with the same CFBundleVersion
# in one directory. Generate arm64 and universal feeds separately, then merge.
log "Generate appcast (per-arch, then merge)"
mkdir -p "$UPDATES"
cp -f "$DMG_ARM64_PATH" "$UPDATES/"
cp -f "$DMG_UNIVERSAL_PATH" "$UPDATES/"

MARKER="$(mktemp)"
ARM_WORK="$(mktemp -d)"
UNI_WORK="$(mktemp -d)"
cleanup_appcast_work() { rm -rf "$ARM_WORK" "$UNI_WORK"; }
trap cleanup_appcast_work EXIT

# arm64 lane: legacy single-arch DMGs (PasteIt-X.Y.Z.dmg) + *-arm64.dmg
shopt -s nullglob
for f in "$UPDATES"/PasteIt-[0-9]*.dmg; do
  base="$(basename "$f")"
  # Skip arch-suffixed builds; those go into their own lane.
  [[ "$base" == *-arm64.dmg || "$base" == *-universal.dmg ]] && continue
  cp -f "$f" "$ARM_WORK/"
done
for f in "$UPDATES"/*-arm64.dmg; do
  cp -f "$f" "$ARM_WORK/"
done
# universal lane
for f in "$UPDATES"/*-universal.dmg; do
  cp -f "$f" "$UNI_WORK/"
done
shopt -u nullglob

[[ "$(ls -A "$ARM_WORK" 2>/dev/null)" ]] || die "arm64 appcast work dir empty"
[[ "$(ls -A "$UNI_WORK" 2>/dev/null)" ]] || die "universal appcast work dir empty"

UPDATES_DIR="$ARM_WORK" "$SCRIPTS/generate-appcast.sh"
UPDATES_DIR="$UNI_WORK" "$SCRIPTS/generate-appcast.sh"

# Collect deltas produced in work dirs into updates/ (sanitize spaces).
shopt -s nullglob
for f in "$ARM_WORK"/*.delta "$UNI_WORK"/*.delta; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  base="${base// /.}"
  cp -f "$f" "$UPDATES/$base"
done
shopt -u nullglob

log "Merge per-arch appcasts + rewrite enclosure URLs → $DOWNLOAD_BASE/mac-v{version}/…"
python3 - "$ARM_WORK/appcast.xml" "$UNI_WORK/appcast.xml" "$UPDATES/appcast.xml" "$DOWNLOAD_BASE" <<'PY'
import re, sys

arm_path, uni_path, out_path, base = sys.argv[1:5]

def split_items(xml: str) -> tuple[str, list[str]]:
    parts = re.split(r"(?=<item>)", xml)
    prefix = parts[0]
    # Drop trailing channel/rss closers that cling to the last item after split.
    chunks = []
    for c in parts[1:]:
        if "<item>" not in c:
            continue
        c = re.sub(r"</channel>\s*</rss>\s*$", "", c, flags=re.I)
        c = re.sub(r"</rss>\s*$", "", c, flags=re.I)
        chunks.append(c)
    # Prefix should only be the open header (no premature closers).
    prefix = re.sub(r"</channel>\s*</rss>\s*$", "", prefix, flags=re.I)
    return prefix, chunks

def short_ver(chunk: str) -> str:
    m = re.search(r"sparkle:shortVersionString(?:>|=\")([0-9]+\.[0-9]+\.[0-9]+)", chunk)
    if not m:
        sys.exit("item without sparkle:shortVersionString")
    return m.group(1)

def build_ver(chunk: str) -> int:
    m = re.search(r"sparkle:version(?:>|=\")([0-9]+)", chunk)
    return int(m.group(1)) if m else 0

def enclosure_name(chunk: str) -> str:
    m = re.search(r'url="([^"]+)"', chunk)
    if not m:
        sys.exit("item without enclosure url")
    return m.group(1).rsplit("/", 1)[-1].replace("%20", ".").replace(" ", ".")

arm_xml = open(arm_path, encoding="utf-8").read()
uni_xml = open(uni_path, encoding="utf-8").read()
prefix, arm_items = split_items(arm_xml)
_, uni_items = split_items(uni_xml)

# Prefer channel header from arm feed; keep highest build per enclosure name.
best: dict[str, str] = {}
for chunk in arm_items + uni_items:
    key = enclosure_name(chunk)
    if key not in best or build_ver(chunk) >= build_ver(best[key]):
        best[key] = chunk

ordered = sorted(best.values(), key=lambda c: (build_ver(c), enclosure_name(c)), reverse=True)

out = [prefix]
for chunk in ordered:
    version = short_ver(chunk)

    def rewrite(match, version=version):
        url = match.group(1)
        name = url.rsplit("/", 1)[-1].replace("%20", ".").replace(" ", ".")
        return f'url="{base}/mac-v{version}/{name}"'

    out.append(re.sub(r'url="([^"]+)"', rewrite, chunk))

body = "".join(out)
if not body.rstrip().endswith("</rss>"):
    body = body.rstrip() + "\n    </channel>\n</rss>\n"

open(out_path, "w", encoding="utf-8").write(body)
print(f"  merged {len(ordered)} item(s) → {out_path}")
PY

trap - EXIT
cleanup_appcast_work

# Delta files produced by this run belong to this release's assets.
ASSETS=("$UPDATES/$DMG_ARM64" "$UPDATES/$DMG_UNIVERSAL")
while IFS= read -r -d '' delta; do
  ASSETS+=("$delta")
done < <(find "$UPDATES" -name '*.delta' -newer "$MARKER" -print0)
rm -f "$MARKER"

# ----------------------------------------------------------- github release
if [[ "$DRY_RUN" -eq 0 ]]; then
  log "Create GitHub Release $TAG on $RELEASE_REPO"
  gh release create "$TAG" "${ASSETS[@]}" \
    --repo "$RELEASE_REPO" \
    --title "Paste It $VERSION" \
    --notes "Paste It for Mac $VERSION (build $NEW_BUILD).

Signed and notarized DMGs:
- \`$DMG_ARM64\` — Apple Silicon (arm64)
- \`$DMG_UNIVERSAL\` — Universal (Intel + Apple Silicon)

Requires macOS $MINIMUM_SYSTEM_VERSION or later."
else
  log "(dry-run: skipping gh release create; assets would be:)"
  printf '  %s\n' "${ASSETS[@]}"
fi

# ------------------------------------------------------------- docs feed
log "Sync appcast → docs/appcast.xml (GitHub Pages)"
mkdir -p "$(dirname "$DOCS_APPCAST")"
cp -f "$UPDATES/appcast.xml" "$DOCS_APPCAST"

# ----------------------------------------------------------- commit and tag
if [[ "$DRY_RUN" -eq 0 ]]; then
  log "Commit + tag"
  git -C "$ROOT" add "$INFO_PLIST" "$DOCS_APPCAST"
  git -C "$ROOT" commit -m "Release Mac $VERSION (build $NEW_BUILD)."
  git -C "$ROOT" tag "$TAG"
  if [[ "$NO_PUSH" -eq 0 ]]; then
    git -C "$ROOT" push origin HEAD "$TAG"
  else
    echo "  (--no-push: run 'git push origin HEAD $TAG' when ready)"
  fi
else
  log "(dry-run: skipping commit/tag/push — Info.plist and docs/appcast.xml are modified locally)"
fi

# ------------------------------------------------------------------- wrapup
cat <<EOF

Release $VERSION ($NEW_BUILD) prepared.

Remaining: enable GitHub Pages from /docs (if not already) so the feed is live:
  $FEED_URL

Verify:
  curl -fsS $FEED_URL | grep -A2 '$VERSION'
  # install the DMG into /Applications, then Settings → About → Check for Updates…

Artifacts:
  DMG arm64:     $DMG_ARM64_PATH
  DMG universal: $DMG_UNIVERSAL_PATH
  dSYM arm64:    $DIST/PasteIt-$VERSION-arm64.dSYM
  dSYM universal:$DIST/PasteIt-$VERSION-universal.dSYM
EOF
