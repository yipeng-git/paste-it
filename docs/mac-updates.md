# Mac auto-updates (Sparkle + GitHub Releases)

Paste It uses **Sparkle 2** for in-app updates. Signed DMGs ship as **GitHub Releases on this same repository**. The stable feed is hosted on this repository’s GitHub Pages:

`https://yipeng-git.github.io/paste-it/appcast.xml` → [`docs/appcast.xml`](appcast.xml)

There is **no** version↔DMG database. The mapping is:

| Source | Role |
| --- | --- |
| Release tag `mac-v{semver}` + assets `PasteIt-{semver}-arm64.dmg` and `PasteIt-{semver}-universal.dmg` on this repo | Download CDN |
| `appcast.xml` (from `generate_appcast`) | What Sparkle polls; each arch build is its own item (`sparkle:version` = `CFBundleVersion`). Apple Silicon prefers the arm64 item (`hardwareRequirements`); Intel uses Universal. |

## Versions

| Field | Rule |
| --- | --- |
| `CFBundleShortVersionString` | Marketing semver (`0.2.0`) in [`Info.plist`](../Info.plist) |
| `CFBundleVersion` | Monotonic integer (Sparkle compares this) |
| Git tag | `mac-v{CFBundleShortVersionString}` |

`scripts/release.sh` manages both fields; don't edit them by hand for releases.

## EdDSA keys

- **Public** key is `SUPublicEDKey` in `Info.plist` (committed).
- Private key lives in the local Keychain after `generate_keys` (item name: **Private key for signing Sparkle updates**). Never commit it.

```sh
# From the pinned tools (auto-downloaded to .tools/sparkle/):
./.tools/sparkle/bin/generate_keys
```

## Release: one command

```sh
./scripts/release.sh 0.2.0
```

This runs the whole chain:

1. Preflight — clean git tree, `gh` auth, Developer ID cert, notary profile, tag/release don't exist yet.
2. Bumps `CFBundleShortVersionString` and `CFBundleVersion` +1.
3. `package-release.sh` — builds **arm64** and **universal** apps, signs, notarizes, staples, writes two DMGs under `dist/`.
4. Regenerates `appcast.xml`; enclosure URLs point at this repo’s Release download URLs.
5. Create a draft GitHub Release on **this repository** and upload both DMGs.
6. Copy the appcast to `docs/appcast.xml`, commit, tag `mac-v{ver}`, and push the exact release commit and tag.
7. Publish the draft only after the tag is available remotely. This prevents GitHub from generating a tag at the previous default-branch commit.

Flags: `--dry-run`, `--skip-package`, `--no-push`. With `--no-push`, the GitHub Release remains a draft until the local commit/tag are pushed and the draft is published.

Override the release target with `PASTEIT_RELEASE_REPO=owner/name` if `origin` is not set yet.

### Remaining step: GitHub Pages

Enable GitHub Pages for this repo from the `/docs` folder (or your preferred static publish path) so `https://yipeng-git.github.io/paste-it/appcast.xml` is reachable after push.

### Verify

```sh
curl -fsS https://yipeng-git.github.io/paste-it/appcast.xml
```

Install the build under `/Applications` and use **Settings → About → Check for Updates…**.

## Local debug

Debug `.app` from `./scripts/run-app.sh` embeds `Sparkle.framework`. Automatic checks still hit the public feed.
