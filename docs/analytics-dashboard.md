# PostHog product dashboard

How to read Paste It’s anonymous analytics: **which journeys matter**, **which metrics to define**, and **how to build them in PostHog**.

Event catalog and privacy disclosure: [`analytics.md`](analytics.md).  
This doc is an **ops / product guide** — not a list of additional collected fields.

Official builds send events to [PostHog Cloud](https://us.i.posthog.com) when a project token is injected. There is **no checked-in dashboard JSON**; create insights in the PostHog UI.

---

## 0. Principles

| Rule | Why |
| --- | --- |
| North star = **`clip_staged`** | User took something from history back to the system pasteboard. We cannot reliably know “pasted into app X”. |
| Prefer **Unique users / persons** | Never treat raw event counts as “users”. |
| Active ≠ `app_open` | Menu-bar apps stay running; `app_open` only fires on process start (or analytics re-enable). **Underestimates DAU**. |
| `app_install` ≠ App Store install | Means **first analytics-enabled run** on this Mac (UserDefaults). Label charts accordingly. |
| Global filter | `app_name = Paste It` (or `$app_name`) if the project might mix products. |
| Default range | Last 30 days; Overview also use Weekly. |

### Recommended metric definitions (use these names on charts)

| Metric | Definition (events) | Notes |
| --- | --- | --- |
| **DAU (recommended)** | Unique persons with `panel_opened` **or** `clip_staged` that day | Primary health |
| **DAU (legacy / underestimate)** | Unique `app_open` | Optional secondary; do not trust alone |
| **WAU** | Unique `panel_opened` or `clip_staged`, weekly | — |
| **New enables** | Unique `app_install` | Proxy for installs |
| **Activation (7d)** | `app_install` → `clip_staged` within 7 days | True “got value” |
| **Panel→Stage conversion** | Sessions with stage / all panel closes | Use `panel_closed` + `did_stage` |
| **Empty-open rate** | `panel_closed` where `did_stage = false` ÷ all `panel_closed` | Inverse of conversion |
| **Retention** | Cohort start `app_install`; return = `panel_opened` or `clip_staged` | **Not** `app_open` |

---

## 1. Journeys to watch

Focus on these five paths. Everything else is secondary until these are readable.

### Path A — Activation

**Question:** After first enable, how soon does someone actually reuse history?

```
app_install
  → onboarding_started (source=first_launch)
  → onboarding_step_viewed… / onboarding_completed
  → panel_opened
  → clip_staged   ← activation success
```

**Watch:** drop-off by onboarding `outcome` / `last_step`; time-to-first-`clip_staged`.  
**Do not** treat “finished tutorial” as activated.

### Path B — Daily reuse (core loop)

**Question:** Of people who open the timeline, how many stage something?

```
panel_opened (source, history_count_bucket)
  → [typed search — searches + zero-result flag on session_summary only]
  → clip_staged (trigger, clip_type, tab, age_bucket)
  → panel_closed (did_stage, duration_ms_bucket)
  → session_summary (stages, searches, search_had_zero_results)
```

**North-star session KPI:** share of panel sessions with `did_stage = true`.

**Search quality (no new event volume):** on `session_summary`, chart share with `search_had_zero_results = true` among sessions with `searches > 0`. Type filters are not tracked.

### Path C — Interaction preferences (within stage)

**Question:** How do people take clips out? Fresh vs old? Which types?

```
clip_staged
  × trigger     (double_click, hotkey_1_9, return, …)
  × clip_type
  × age_bucket
  × tab
```

**Use for:** shortcut teaching, default retention, plain-text defaults.

### Path D — Onboarding quality

**Question:** Where do people bail, and does finishing correlate with later stage?

```
onboarding_started
  → step views
  → onboarding_completed (outcome, last_step)
```

Cross-check: completers vs skippers → 7d `clip_staged` (cohort or funnel).

### Path E — Paste Stack

**Question:** Is Stack discovered? Does Accessibility block Paste Next?

```
paste_stack_session   ← one event per open→close (quota-friendly)
  direction, collected_count_bucket, paste_next_count / attempts,
  accessibility_trusted_at_open / _at_close, paste_next_without_ax,
  empty_paste_next_count, last_fail_reason?
```

**Charts:** Unique users with `paste_stack_session`; share with `paste_next_count > 0`; share with `accessibility_trusted_at_close = false` or `paste_next_without_ax > 0`.

### Path F — Update adoption

**Question:** Do auto-updates land? Where does the Sparkle funnel stall?

```
update_interaction
  action: check → found → download → install
  (+ dismiss / fail)
  source: auto | menu | settings
```

**Caveat:** `download` may fire more than once (will/did); filter or split with `result` using live event samples.

### Paths not instrumented yet (do not build charts for these)

| Path | Status |
| --- | --- |
| Pin / folder / edit / delete | Not wired (defer — more events) |
| Capture pause / ignored apps / MCP toggle | Not wired |

---

## 2. Dashboard layout

Create **one** dashboard:

**Name:** `Paste It — Product`

**Sections (top → bottom):**

1. Overview (health)
2. Activation & onboarding
3. Core loop (panel → stage)
4. Stage breakdowns
5. Paste Stack
6. Updates

Optional later: pin/folder/MCP once those events exist.

---

## 3. Insights to configure

### 3.1 Overview (health)

| Chart name | Type | Configuration |
| --- | --- | --- |
| **DAU (panel)** | Trends | Event `panel_opened` → **Unique users** → Interval **Day** → Last 30 days |
| **DAU (stage)** | Trends | Event `clip_staged` → Unique users → Day |
| **WAU (panel)** | Trends | Same as DAU panel, interval **Week** |
| **New enables** | Trends | `app_install` → Unique users → Day. Subtitle: *first analytics enable, not App Store install* |
| **Retention (install → panel)** | Retention | Start: `app_install`. Return: `panel_opened`. (Alt return: `clip_staged`) |
| **Version mix** | Trends | `panel_opened` → Unique users → Breakdown `app_version` (or `app_open` if needed for process-start cohort) |
| **DAU (app_open) — optional** | Trends | `app_open` Unique users → Day. Label clearly as **underestimate** |

**Formula / paired series (empty opens):**

- Series A: `panel_closed` where `did_stage = true`
- Series B: `panel_closed` (all)
- Formula `A / B` → name **Panel sessions with stage**  
- Empty-open rate ≈ `1 - A/B`, or chart B−A / B separately

### 3.2 Activation & onboarding

| Chart name | Type | Configuration |
| --- | --- | --- |
| **Install → Stage (7d)** | Funnel | Step 1 `app_install` → Step 2 `clip_staged`. Conversion window **7 days**. Primary activation KPI |
| **Onboarding steps (first launch)** | Funnel | Filter `source = first_launch` on start where applicable. Steps: `onboarding_started` → `onboarding_step_viewed` (`step=capture`) → (`timeline`) → (`stage`) → `onboarding_completed` (`outcome=completed`) |
| **Onboarding outcomes** | Trends | `onboarding_completed` → Breakdown `outcome` (`completed` / `skipped` / `dismissed`) |
| **Bail-out step** | Trends | `onboarding_completed` where `outcome` is `skipped` or `dismissed` → Breakdown `last_step` |

### 3.3 Core loop

| Chart name | Type | Configuration |
| --- | --- | --- |
| **Panel opens** | Trends | `panel_opened`: Unique users **and** Total count (two series or two charts) |
| **Open by source** | Trends | `panel_opened` → Breakdown `source` (`hotkey` / `status_item` / `menu`) |
| **History size at open** | Trends | `panel_opened` → Breakdown `history_count_bucket` |
| **Session duration** | Trends | `panel_closed` → Breakdown `duration_ms_bucket` |
| **Panel → Stage** | Funnel | `panel_opened` → `clip_staged`. Prefer short window (e.g. 10–30 min). Ideal: same `session_id` if PostHog funnel supports property matching; else person + time window |
| **Sessions with stage** | Trends + Formula | See Overview empty-open pair (`did_stage`) |
| **Session intensity** | Trends | `session_summary` — average of `stages` / `searches` (as PostHog allows) |
| **Search zero-result rate** | Trends + Formula | Among `session_summary` with `searches > 0`, share with `search_had_zero_results = true` |

### 3.4 Stage breakdowns

| Chart name | Type | Configuration |
| --- | --- | --- |
| **Stage by trigger** | Trends | `clip_staged` → Breakdown `trigger` |
| **Stage by clip type** | Trends | `clip_staged` → Breakdown `clip_type` |
| **Stage by age** | Trends | `clip_staged` → Breakdown `age_bucket` |
| **Stage by tab** | Trends | `clip_staged` → Breakdown `tab` |

### 3.5 Paste Stack

| Chart name | Type | Configuration |
| --- | --- | --- |
| **Stack sessions** | Trends | `paste_stack_session` → Unique users + Total count |
| **Stack collected size** | Trends | Breakdown `collected_count_bucket` |
| **Used Paste Next** | Trends / Formula | Sessions with `paste_next_count > 0` ÷ all `paste_stack_session` |
| **AX friction** | Trends | Filter `accessibility_trusted_at_close = false` **or** `paste_next_without_ax > 0` |
| **Direction mix** | Trends | Breakdown `direction` (`fifo` / `lifo`) |

### 3.6 Updates

| Chart name | Type | Configuration |
| --- | --- | --- |
| **Update funnel** | Funnel or Trends | Filter `update_interaction` by `action`: `check` → `found` → `download` → `install`. Validate enum values in Live events first |
| **Update by source** | Trends | `update_interaction` → Breakdown `source` |
| **Update failures** | Trends | `update_interaction` where `action`/`result` indicates fail (from live samples) |
| **From → to version** | Trends | Breakdown `from_version` (and `to_version` when present) |

---

## 4. Step-by-step: create the dashboard in PostHog

### 4.0 Confirm data

1. Left nav → **Data** / **Events** (or Activity / Live events).
2. Confirm recent `app_open`, `panel_opened`, `clip_staged`.
3. Open one event and verify property names (`did_stage`, `source`, `trigger`, …) match [`analytics.md`](analytics.md).

No events → use a **Developer ID–signed** build with `Secrets/posthog.env` injected; Settings → Privacy → analytics on.

### 4.1 New dashboard

1. **Dashboards** → **New dashboard**
2. Name: `Paste It — Product`
3. Optional: pin to project home

### 4.2 Minimum viable board (build these first)

Do these six before polishing:

1. **DAU (panel)** — Trends / `panel_opened` / Unique users / Day  
2. **New enables** — Trends / `app_install` / Unique users / Day  
3. **Install → Stage (7d)** — Funnel  
4. **Onboarding outcomes** — Trends / breakdown `outcome`  
5. **Sessions with stage** — `panel_closed` + `did_stage` formula (or two series)  
6. **Stage by trigger** — Trends / breakdown `trigger`

Then add open-by-source, age/type breakdowns, retention, and update funnel.

### 4.3 Adding any Trends insight

1. Dashboard → **Add insight** → **Trends**
2. Pick event → set aggregation to **Unique users** (unless you intentionally want Total count)
3. Interval Day/Week → date range Last 30 days
4. Optional **Breakdown** by property
5. Optional **Filter** (e.g. `did_stage = true`, `is_duplicate_skip = false`)
6. Rename clearly → **Save & add to dashboard**

### 4.4 Adding a Funnel

1. **Add insight** → **Funnel**
2. Add ordered steps (events + property filters per step)
3. Set **conversion window** (activation: 7 days; panel→stage: minutes–hours)
4. Save to dashboard

### 4.5 Adding Retention

1. **Add insight** → **Retention**
2. Start event: `app_install`
3. Return event: `panel_opened` (or `clip_staged`)
4. Save

---

## 5. How to read the board (decision cues)

| If you see… | Likely product action |
| --- | --- |
| High panel opens, low `did_stage` | Empty-open / discovery problem; check duration buckets and `history_count_bucket = 0` |
| High `search_had_zero_results` among searchers | Search / empty-state UX |
| Many `paste_stack_session`, low `paste_next_count` | Stack opened but unused — teach Paste Next / ⌘V |
| `paste_next_without_ax` or AX false at close | Accessibility onboarding / empty-state CTA |
| Activation funnel dies before `clip_staged` | Onboarding or first-open UX; check bail `last_step` |
| Most stages are `age_bucket = <1m` | Users treat it as “recent clipboard”; retention defaults less critical |
| Many stages are older buckets | History depth / search / pin matter more |
| `source` dominated by `status_item`, little `hotkey` | Hotkey discoverability |
| `trigger` mostly `double_click`, little `hotkey_1_9` | Shortcut education |
| Update `found` high, `install` low | Sparkle / permission / UX stall |
| DAU(panel) ≫ DAU(app_open) | Expected for menu-bar app — trust panel/stage |

---

## 6. Privacy reminders for analysts

- Never request clipboard text, OCR text, paths, or full search queries in new events.
- Search quality: `searches` + `search_had_zero_results` on **`session_summary`** only — never send the query string. Type filters are not tracked.
- Paste Stack emits **one** `paste_stack_session` per open→close (not per paste-next).
- Clipboard capture is not reported (quota); infer inventory from `history_count_bucket` / stage types.
- Opt-out: Settings → Privacy; client stops sending (`optOut`).
- Uninstall is not observable; churn = silence on panel/stage.

---

## 7. Related

- Event list: [`analytics.md`](analytics.md)
- Client: `Sources/PasteIt/Analytics/`
- Packaging / token inject: [`mac-packaging.md`](mac-packaging.md)
