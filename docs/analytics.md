# Analytics disclosure

Paste It may send **anonymous product analytics** to [PostHog](https://posthog.com) to improve the app. Analytics is **on by default** and can be turned off in **Settings → Privacy**.

This document is the public catalog of what is collected. The same list is shown in-app under **Settings → Privacy → What we collect**, and is defined in code as `AnalyticsCatalog`.

## Principles

- **No clipboard contents** — never text, HTML, RTF, previews, OCR, images, file bytes, or local paths.
- **No search strings** — only that a search happened during a panel session (count), never the query.
- **No accounts** — anonymous device ID from the PostHog SDK; we do not call `identify` with a user id.
- **Opt out anytime** — disabling analytics stops further events (`optOut`).

Official builds inject a PostHog project token at package time (`Secrets/posthog.env`). Builds without a token send nothing.

## Common properties (every event)

Registered via PostHog `register`:

| Property | Meaning |
| --- | --- |
| `app_name` / `$app_name` | `"Paste It"` |
| `app_version` / `$app_version` | Marketing version |
| `app_build` | Build number |
| `platform` | `"macos"` |
| `os` / `$os` | `"macOS"` |
| `os_version` / `$os_version` | OS version |
| `first_open_utc` | First analytics-enabled open (ISO8601) |

The PostHog SDK may also attach its own library/device fields.

## Lifecycle events

| Event | When | Properties |
| --- | --- | --- |
| `app_install` | First analytics-enabled run on this Mac | `install_utc` |
| `app_open` | Launch, or analytics re-enabled | — |
| `app_exit` | Clean quit | — |

## Product events (P0)

| Event | When | Properties (metadata only) |
| --- | --- | --- |
| `onboarding_started` | Tutorial opens | `source`: `first_launch` \| `settings` |
| `onboarding_step_viewed` | Tutorial page shown | `step`: `welcome` \| `capture` \| `timeline` \| `stage` \| `nextSteps` |
| `onboarding_completed` | Finish / skip / window close | `outcome`: `completed` \| `skipped` \| `dismissed`; `last_step` |
| `panel_opened` | Timeline panel shown | `source`: `hotkey` \| `status_item` \| `menu`; `history_count_bucket`; `session_id` |
| `panel_closed` | Timeline panel hidden | `duration_ms_bucket`; `did_stage`; `session_id` |
| `session_summary` | Same moment as panel close | `opens`; `stages`; `searches`; `captures_while_open`; `session_id` |
| `clip_captured` | Clipboard history add / dedupe | `clip_type`; `has_ocr_scheduled`; `is_duplicate_skip` |
| `clip_staged` | Item staged to system pasteboard from timeline | `mode`; `trigger`; `clip_type`; `tab`; `age_bucket`; `session_id?` |
| `update_interaction` | Sparkle update funnel | `action`; `source` (`auto` \| `menu` \| `settings`); `from_version`; `to_version?`; `result?` |

### Buckets (fixed cardinality)

- `history_count_bucket`: `0` · `1-10` · `11-50` · `51-200` · `200+`
- `duration_ms_bucket`: `<1s` · `1-3s` · `3-10s` · `10-30s` · `30-60s` · `60s+`
- `age_bucket`: `<1m` · `<1h` · `<1d` · `<1w` · `older`

### `clip_type` values

`text` · `richText` · `html` · `image` · `file` · `url` · `mixed`

### `clip_staged.trigger` values

`double_click` · `hotkey_1_9` · `return` · `shift_return` · `cmd_c` · `context_menu`

## Never collected

- Clipboard text, HTML, RTF, or previews
- OCR text from images
- Image / file bytes or local paths
- Full search query strings
- Clip titles (often derived from content)
- Source app clipboard payloads
- MCP / Agent API payloads

## Implementation

- Client: `Sources/PasteIt/Analytics/`
- Sparkle hooks: `Sources/PasteIt/App/UpdateChecker.swift`
- Toggle: `AppSettings.analyticsEnabled` → Settings → Privacy

macOS does **not** provide a reliable uninstall callback; churn is inferred from silence (`app_open` / panel activity), not an `uninstall` event.
