# Product experience improvement roadmap

Created: September 8, 2026

Status: UX-01–UX-03 implemented; live interaction verification is partially pending. UX-04–UX-12 remain planned.

## Purpose and evidence

Make finding and reusing clipboard content fast, predictable, and recoverable. The primary journeys are reusing a recent clip, finding an older clip, and filling several destinations with a sequence of clips.

This backlog translates the product review into individually implementable work items. Current-behavior observations come from source inspection, the README, and repository screenshots. They are not findings from a completed usability study or a new live-app verification session. The problem statements preserve that review baseline; see the implementation record for delivered changes. Recheck the relevant implementation when starting each item.

The target behaviors below are working product recommendations. Where a default or migration policy needs refinement, record the final decision in that item's implementation notes. Do not describe a proposed capability as already available in user documentation.

Performance work is tracked separately in [the performance review](performance-review.md). Preserve its improvements to search cancellation, stable list identity, media loading, and notification coalescing.

## Delivery order

P0 protects predictable actions and user data. P1 improves task completion and recovery. P2 improves discoverability and presentation. These are roadmap priorities, not production incident severity levels.

| Order | ID | Priority | Deliverable | Status | Depends on |
| --- | --- | --- | --- | --- | --- |
| 1 | UX-01 | P0 | Consistent selection, copy, and paste actions | Implemented — verification pending | — |
| 2 | UX-02 | P0 | Visible permission and failure recovery | Implemented — verification pending | UX-01 |
| 3 | UX-03 | P0 | Clear removal scope and deletion recovery | Implemented — verification pending | — |
| 4 | UX-04 | P0 | Predictable editing and preservation of originals | Planned | UX-01 |
| 5 | UX-05 | P1 | Recoverable Paste Stack sessions | Planned | UX-02 |
| 6 | UX-06 | P1 | Explicit multi-selection order and copy behavior | Planned | UX-01, UX-02 |
| 7 | UX-07 | P1 | Discoverable search and understandable results | Planned | UX-01 |
| 8 | UX-08 | P1 | Context continuity between consecutive uses | Planned | UX-07 |
| 9 | UX-09 | P2 | Content-focused cards and a compact view | Planned | UX-06, UX-07 |
| 10 | UX-10 | P2 | First successful reuse as the onboarding goal | Planned | UX-01, UX-02 |
| 11 | UX-11 | P2 | Task-oriented settings and configurable shortcuts | Planned | UX-01 |
| 12 | UX-12 | P2 | Visible capture state and understandable privacy controls | Planned | UX-02, UX-03 |

Implement one item at a time, in the order above. Keep the status table current using Planned, In progress, Implemented — verification pending, Done, or Blocked. Mark an item Done only after its applicable acceptance checks pass. A blocked item must identify the specific missing prerequisite; continue independent work when possible.

## UX-01 — Consistent selection, copy, and paste actions

**Problem.** Single-click selects, double-click and Command–1…9 copy and dismiss, and Return auto-pastes. Dismissal therefore represents different outcomes. The README also says selecting copies, which does not match the single-click implementation.

**Target behavior.**

- Single-click selects without changing the system clipboard. Space opens or closes preview.
- Double-click, Return, and Command–1…9 share a primary action: Paste or Copy Only. The setting and documentation must describe the actual action.
- Command–C and the Copy button explicitly copy while keeping the panel open. Shift–Return remains an explicit plain-text paste action.
- Preserve the main panel’s original layout, 320-point height, and controls. Do not add a footer or persistent shortcut hints. Put action explanations in Settings and operation-triggered recovery dialogs.
- Default all installations to Direct Paste without a compatibility mode. Preserve an explicitly chosen Copy Only preference; normalize missing, obsolete, or invalid values to Direct Paste.
- Update the affected README translations, tutorial copy, tooltips, and shortcuts together.

**Acceptance criteria.**

- [x] Single-click and preview leave clipboard content unchanged.
- [ ] Double-click, Return, and numeric activation produce the same action and dismissal behavior for a single clip.
- [ ] Explicit copy and plain-text paste remain independently available and correctly labeled.
- [x] Reopening or restarting preserves the selected action setting; new and existing installs use the same default without trigger-specific exceptions. (Settings reinitialization and migration tests.)
- [ ] Verify text, rich text, images, and files, plus interaction with an active Stack. App-generated writes must not be captured again.

**Implementation entry points:** [TimelineView](../Sources/PasteIt/UI/Timeline/TimelineView.swift), [AppState](../Sources/PasteIt/App/AppState.swift), [AppSettings](../Sources/PasteIt/App/AppSettings.swift), [CardClickOverlay](../Sources/PasteIt/UI/Components/CardClickOverlay.swift).

## UX-02 — Visible permission and failure recovery

**Problem.** Without Accessibility permission, Return on one clip falls back to copying and dismisses the panel. The explanatory status is rendered inside the dismissed panel and expires after two seconds. Some failed writes return without a useful visible explanation.

**Target behavior.**

- Explain the manual copy/paste fallback and provide an Enable Direct Paste entry point in Settings. If a paste is attempted without permission, show an operation-triggered dialog with the next step; do not add controls to the main panel layout.
- Explain why Accessibility is needed and provide a route to the relevant system settings. Refresh permission state when the user returns.
- Keep errors visible until resolved or dismissed. Successful actions can use brief, unobtrusive feedback.
- Failed writes preserve the selection and provide Retry or a supported alternative.
- Distinguish a successful clipboard write, a dispatched paste request, and verified insertion into a destination. Sending Command–V does not prove the destination accepted it.

**Acceptance criteria.**

- [ ] A user without permission can complete manual copy/paste and sees the required next step.
- [ ] Permission explanations remain visible rather than disappearing with the timeline.
- [ ] Returning from system settings updates the available action without restarting the app.
- [ ] A missing attachment or failed write does not report success or lose selection.
- [ ] Direct paste restores the intended destination focus and does not interact with the search field or preview editor.

**Implementation entry points:** [TimelineView](../Sources/PasteIt/UI/Timeline/TimelineView.swift), [PasteController](../Sources/PasteIt/Core/PasteController.swift), [SystemPasteSynthesizer](../Sources/PasteIt/Core/SystemPasteSynthesizer.swift), [AppState](../Sources/PasteIt/App/AppState.swift).

## UX-03 — Clear removal scope and deletion recovery

**Problem.** Removing an ordinary history clip deletes it, while removing a saved clip from history only hides it there. Removing from Pinned or a folder changes membership. Bulk-clear buttons execute immediately, and the reviewed deletion paths have no explicit recovery flow.

**Target behavior.**

- Use scope-specific actions: Remove from History, Unpin, Remove from “<folder name>”, and Delete Everywhere… where applicable.
- Make clear when a clip remains saved elsewhere. Keep icons and labels consistent with the action's scope.
- Ordinary removal shows a three-second toast with an Undo button. Hover pauses the countdown; pointer exit resumes the remaining time. Anchor a non-key child panel 12 points above the timeline, centered horizontally, without changing its layout. Use native Clear Liquid Glass with bright text and localized dimming on macOS 26+, with a dark HUD-material fallback on older macOS versions. Short messages use a content-sized 44-point capsule; long messages wrap into a rounded rectangle. Restore content, membership, and position together.
- Toast dismissal does not end the original 30-second undo window: the existing menu and Command–Z remain available. A toast targets its own removal; it must never undo a different record after replacement or expiry. Expired Undo actions disappear even if the toast is still hovered. Closing the panel dismisses transient feedback without discarding undo history.
- Before bulk clearing or shortening retention in a way that removes records, show the affected count and whether saved clips are included.
- Define the recovery lifetime explicitly. Retain required attachments while an undo operation remains available, and do not imply that permanently deleted content is recoverable.

**Acceptance criteria.**

- [x] Check ordinary, pinned, folder-only, and multiply saved clips from each relevant tab. (Store integration tests; live controls still pending.)
- [x] Undo restores the clip and its memberships without creating duplicates or missing attachments. (Synthetic storage, deduplication, ordering, and attachment protection tests.)
- [ ] Bulk deletion names its scope and affected count; cancelling preserves all records.
- [ ] Retention changes explain imminent removal before applying it.
- [ ] User-facing copy distinguishes removal from one view from deletion everywhere.
- [x] Toast expiration, hover pause/resume, replacement, and stale undo identity are covered by automated tests. Folder names appear in action and success copy, and dismissing the toast preserves store undo.
- [x] Native hosting and child-window tests cover capsule sizing, long-message wrapping, same-display placement, visible-screen bounds, fixed parent geometry, and non-key focus behavior.
- [x] Signed-app synthetic screenshots verify the above-panel capsule, long-folder-name rounded rectangle, gap, and readable native Liquid Glass rendering in the current appearance.
- [ ] Verify live Undo clicks and hovering, dark appearance, and accessibility settings.

**Implementation entry points:** [HistoryStore](../Sources/PasteIt/Storage/HistoryStore.swift), [TimelineView](../Sources/PasteIt/UI/Timeline/TimelineView.swift), [CardHoverActionBar](../Sources/PasteIt/UI/Components/CardHoverActionBar.swift), [SettingsView](../Sources/PasteIt/Settings/SettingsView.swift).

## UX-04 — Predictable editing and preservation of originals

**Problem.** Ordinary text edits commit on focus loss or preview dismissal, including the editing Escape path. OCR uses explicit Save and Cancel. A temporary correction for one paste can therefore modify the historical original unexpectedly.

**Target behavior.**

- Start editing in a draft that leaves the saved original unchanged.
- Provide distinct actions: Paste Edited Copy and Save Changes. An explicit copy action can support the manual-paste path.
- Use the same Save, Cancel, and Escape semantics for plain text, rich text, and OCR editing.
- Switching clips or dismissing a preview must not silently save or lose a changed draft. Preserve the draft for the current session or offer an explicit Save/Discard/Continue Editing choice.
- Saving refreshes search and preview content. A temporary paste must not mutate the original or create a duplicate through self-capture.

**Acceptance criteria.**

- [ ] Cancel and Escape during editing leave the original unchanged.
- [ ] Paste Edited Copy uses the draft while retaining the original history item and its folder memberships.
- [ ] Save Changes updates the intended record and relevant search results.
- [ ] Clip switching, outside clicks, and panel closure handle unsaved drafts consistently.
- [ ] Rich formatting survives supported edits; OCR editing does not alter image pixels.

**Implementation entry points:** [ClipQuickPreview](../Sources/PasteIt/UI/Timeline/ClipQuickPreview.swift), [RichTextEditor](../Sources/PasteIt/UI/Components/RichTextEditor.swift), [HistoryStore](../Sources/PasteIt/Storage/HistoryStore.swift).

## UX-05 — Recoverable Paste Stack sessions

**Problem.** Closing Stack clears its queue. Staging removes an item before the clipboard write succeeds. An accidental close or a failed write can lose the user's sequence. Collection state alone does not fully explain whether Command–V is currently intercepted.

**Target behavior.**

- Separate Collapse, Pause, and End & Clear. Collapse preserves a visible compact indicator while active; Pause preserves the queue and restores normal Command–V.
- Map the close affordance and toggle shortcut to a documented, non-destructive pause/hide behavior. Reserve clearing for an explicitly named action.
- Display the next item, remaining count, paste direction, and active/paused state.
- Advance only after a successful clipboard write and paste dispatch. Keep failed items available for retry; do not claim destination acceptance.
- Provide Paste Previous Again for correcting a misplaced paste. Retain only the bounded session state needed for this operation.
- Handle rapid Command–V presses in order without duplicate delivery, lost items, or continued delivery after pause/end.

**Acceptance criteria.**

- [ ] Pause and resume retain exact queue order; normal Command–V works while paused.
- [ ] Collapsing an active queue leaves an obvious way to identify and pause it.
- [ ] A failed write retains the pending item and shows a recovery action.
- [ ] Paste Previous Again does not consume the next item.
- [ ] Verify both directions, queue exhaustion, repeated values, rapid paste requests, and pause/end during delivery.
- [ ] Define and document what remains in the system clipboard when the queue pauses, ends, or becomes empty.

**Implementation entry points:** [PasteStackController](../Sources/PasteIt/Features/PasteStack/PasteStackController.swift), [PasteStackView](../Sources/PasteIt/Features/PasteStack/PasteStackView.swift), [PasteStackPanelController](../Sources/PasteIt/Features/PasteStack/PasteStackPanelController.swift).

## UX-06 — Explicit multi-selection order and copy behavior

**Problem.** Multi-selection pastes in visible left-to-right order, not click order. The interface mainly shows a count. Command–C silently copies only the first selected item and collapses selection.

**Target behavior.**

- Preserve visual order as the initial rule and display numbered badges for the actual delivery sequence. Distinguish these from Command–1…9 activation badges.
- Show an action-specific summary, such as `Paste 3 items in displayed order`.
- For multiple text-compatible clips, support Copy Combined Text with a visible separator choice; use a newline as the initial default.
- Do not silently discard non-text items or collapse multi-selection when a combined copy is unsupported. Explain the limitation and retain selection.
- Explain that batch paste writes several items to the same focused destination, while Stack lets the user move between destinations.

**Acceptance criteria.**

- [ ] Out-of-order clicking produces badges that accurately predict paste order.
- [ ] Selection changes and filtering update numbering without stale or duplicate positions.
- [ ] Combined text includes every selected compatible item with the chosen separator.
- [ ] Mixed unsupported selections receive an explanation without changing clipboard content or selection.
- [ ] Batch paste preserves destination focus and does not advance an active Stack.

**Implementation entry points:** [AppState](../Sources/PasteIt/App/AppState.swift), [TimelineView](../Sources/PasteIt/UI/Timeline/TimelineView.swift), [ClipCardView](../Sources/PasteIt/UI/Timeline/ClipCardView.swift).

## UX-07 — Discoverable search and understandable results

**Problem.** Search already supports text, OCR, type, source application, and date operators. Type filtering is visible, but source/date capabilities require syntax knowledge. Search requires explicit activation, and image results do not necessarily explain the OCR match.

**Target behavior.**

- Typing printable text from the browsing state starts search without losing the first character. Preserve navigation shortcuts, Space preview, editor input, and input-method composition.
- Expose source application and date filters as visible controls with removable chips. Keep existing query operators available.
- Show a matched OCR excerpt on image results and emphasize the matching content in text/link results.
- Show the search scope and relevant empty-state recovery actions: Clear Filters, Search All History, or Clear Search.
- Keep stale asynchronous results from replacing a newer query's results.

**Acceptance criteria.**

- [ ] Direct typing works with English and Chinese/Japanese input methods without consuming composition keystrokes.
- [ ] Source, date, and type controls combine consistently with text and supported operators.
- [ ] An OCR-only hit includes an understandable excerpt without opening every image.
- [ ] Empty results explain the active scope and offer a useful next action.
- [ ] Rapid typing, clearing, and tab switching preserve latest-query-wins behavior and responsiveness.

**Implementation entry points:** [TimelineView](../Sources/PasteIt/UI/Timeline/TimelineView.swift), [TimelineFilterButton](../Sources/PasteIt/UI/Components/TimelineFilterButton.swift), [SearchService](../Sources/PasteIt/Search/SearchService.swift), [AppState](../Sources/PasteIt/App/AppState.swift).

## UX-08 — Context continuity between consecutive uses

**Problem.** Reopening resets the query, tab, source filter, selection, and scroll position. Repeated use of a folder or search result requires the same navigation again.

**Target behavior.**

- Resume tab, query, filters, selection, and scroll position during a short reuse session.
- Working session window: 60 seconds after dismissal. Outside that window, open recent history. Keep this as an internal policy initially rather than adding another preference.
- Provide an explicit Back to Recent action that clears the browsing context immediately.
- If the selected clip or folder disappears, recover to a valid nearby selection or recent history.

**Acceptance criteria.**

- [ ] Reopen within the session window resumes the same useful context after copy or paste.
- [ ] Reopen after the window returns to recent history; Back to Recent does so immediately.
- [ ] New captures, deleted selections, and removed folders do not create stale references or unexpected jumps.
- [ ] The normal first-open path still has correct leading inset, focus, and selection.

**Implementation entry points:** [AppState](../Sources/PasteIt/App/AppState.swift), [TimelinePanelController](../Sources/PasteIt/UI/TimelinePanelController.swift), [TimelineView](../Sources/PasteIt/UI/Timeline/TimelineView.swift).

## UX-09 — Content-focused cards and a compact view

**Problem.** Fixed 238 × 232 cards with a 52-point header favor visual recognition but expose relatively few short text clips at once. The benefit of a denser presentation is a usability hypothesis to validate.

**Target behavior.**

- Retain the card timeline and add an optional compact list for text-heavy tasks. Persist the chosen view; do not force a view change when searching.
- Prioritize distinguishing content and search excerpts over repeated type labels.
- Display saved/pinned membership without requiring hover. Keep source, time, and media previews available.
- Preserve the same action, selection, ordering, preview, and keyboard rules across views.

**Acceptance criteria.**

- [ ] Compare finding short synthetic clips in card and compact views using the same dataset.
- [ ] Both views pass the same single/multi-selection and action scenarios.
- [ ] Verify light/dark appearance, long translated labels, CJK text, keyboard focus, and meaningful accessibility labels.
- [ ] Increased density does not regress scrolling, search responsiveness, or media loading.

**Implementation entry points:** [ClipCardView](../Sources/PasteIt/UI/Timeline/ClipCardView.swift), [TimelineView](../Sources/PasteIt/UI/Timeline/TimelineView.swift), [CardHoverActionBar](../Sources/PasteIt/UI/Components/CardHoverActionBar.swift).

## UX-10 — First successful reuse as the onboarding goal

**Problem.** The first-run tutorial spans capture, selection, preview/edit, multi-selection, and Stack. Viewing all pages does not demonstrate that a user can successfully reuse a clip.

**Target behavior.**

- Lead with a short practical exercise: copy a synthetic example, open history, choose it, and paste into a clearly identified test input.
- Introduce permission at the direct-paste step and provide a working manual-paste route.
- Teach preview, multi-selection, and Stack contextually when first relevant. Make tips dismissible and the tutorial replayable.
- Distinguish tutorial dismissal from successful completion of the exercise.

**Acceptance criteria.**

- [ ] A new user can complete the core loop without learning advanced features first.
- [ ] Both granted and unavailable Accessibility paths lead to a successful exercise.
- [ ] Skipping/replaying works, and dismissed contextual tips do not repeatedly interrupt work.
- [ ] The exercise uses synthetic data and does not inspect unrelated destination content.

**Implementation entry points:** [OnboardingPage](../Sources/PasteIt/Onboarding/OnboardingPage.swift), [OnboardingView](../Sources/PasteIt/Onboarding/OnboardingView.swift), [OnboardingWindowController](../Sources/PasteIt/Onboarding/OnboardingWindowController.swift).

## UX-11 — Task-oriented settings and configurable shortcuts

**Problem.** Settings opens with About before operational controls. Global shortcuts are fixed, and registration failures are principally logged. Clipboard polling appears alongside routine preferences as a technical parameter.

**Target behavior.**

- Open Settings to General and group controls by user task: capture, paste, shortcuts, privacy, and storage. Keep About available but secondary.
- Allow editing global timeline, Stack, and plain-text shortcuts, with restore-default actions.
- Report registration failure visibly and preserve the last working binding. Do not claim detection of conflicts that the system cannot report.
- Update displayed shortcut hints and tutorial instructions from the effective bindings.
- Move polling and similar tuning to an Advanced group with a short explanation.
- Show meaningful storage usage and the scope of cleanup actions instead of only a capacity limit.

**Acceptance criteria.**

- [ ] Valid shortcut changes work immediately and survive restart.
- [ ] Failed registration does not leave the feature without its previous working shortcut; menu access remains available.
- [ ] Reset restores defaults and all visible hints match the actual bindings.
- [ ] Routine settings are discoverable without opening About or interpreting polling internals.
- [ ] Storage counts/usage are labeled accurately and agree with cleanup scope.

**Implementation entry points:** [SettingsView](../Sources/PasteIt/Settings/SettingsView.swift), [HotkeyManager](../Sources/PasteIt/Core/HotkeyManager.swift), [AppSettings](../Sources/PasteIt/App/AppSettings.swift), [AppRuntime](../Sources/PasteIt/App/AppRuntime.swift).

## UX-12 — Visible capture state and understandable privacy controls

**Problem.** Pause is available in menus/settings but is not prominent in the timeline. An empty history can still instruct the user to copy while capture is paused. Local storage, optional analytics, and network requests for link previews are separate behaviors that deserve clear explanations.

**Target behavior.**

- Display paused capture state in the menu bar and timeline with Resume and timed pause options, initially 15 minutes, 1 hour, and Until Resumed.
- Make empty-state guidance reflect paused capture and current filters.
- Lead privacy settings with capture state, excluded applications, retention, and cleanup controls.
- Explain that history is stored locally while fetching link previews visits the linked website. Provide an automatic-preview toggle; when disabled, offer an explicit load action and do not fetch new previews automatically.
- Present the optional analytics choice clearly during onboarding. Preserve existing opt-out choices; never re-enable analytics through onboarding or updates.
- Describe MCP separately as optional local agent access and retain its disabled-by-default behavior.

**Acceptance criteria.**

- [ ] Paused capture is visible without opening Settings, and paused empty states offer Resume.
- [ ] Timed pause resumes correctly after sleep; record and test the policy for restart during a timed pause.
- [ ] Disabling automatic link previews prevents new automatic requests; explicit loading remains available and clearly labeled.
- [ ] Analytics opt-out survives restart, update, and tutorial replay.
- [ ] Ignored applications, protected clipboard types, and MCP defaults retain their existing protections.

**Implementation entry points:** [PrivacySettingsView](../Sources/PasteIt/Settings/PrivacySettingsView.swift), [AppRuntime](../Sources/PasteIt/App/AppRuntime.swift), [AppSettings](../Sources/PasteIt/App/AppSettings.swift), [LinkMetadataService](../Sources/PasteIt/Search/LinkMetadataService.swift), [LinkWebPreview](../Sources/PasteIt/UI/Components/LinkWebPreview.swift).

## Verification and completion policy

For each item, update its status, tick only verified acceptance criteria, and append an implementation record with the date, final product decisions, changed behavior, checks performed, evidence, and remaining limitations. Keep unverified UI behavior explicitly pending.

- Follow [AGENTS.md](../AGENTS.md). Documentation-only work requires path/content checks and `git diff --check`, not an app build.
- For core changes, run meaningful regression tests and build the application. Avoid implementation-mirroring tests for low-impact presentation changes.
- For gestures, selection, editing, shortcuts, permissions, or paste behavior, package a Developer ID–signed arm64 build, install it in Applications, launch it, and verify the installed signing authority. Follow [the packaging guide](mac-packaging.md); local verification may skip notarization.
- Use synthetic clips and temporary test stores. Never clear real history, reset user permissions, or expose clipboard content to make a test easier.
- Test applicable permission states using available environments without resetting existing grants. If a state cannot be exercised, record it as unverified.
- Check the relevant text/rich-text/image/file cases, focus restoration, clipboard self-capture suppression, and interaction with Stack.
- Update localized resources and affected README versions when behavior or shortcuts change.

## Product validation tasks

Collect a baseline before changing the relevant journey, then repeat the same task and dataset after implementation. These are proposed measurements, not existing results or promised performance targets.

| Task | Observe | Improvement signal |
| --- | --- | --- |
| Reuse a short clip copied one minute earlier | Time from opening history to observed insertion; wrong actions; help requests | Faster correct completion with fewer copy/paste misunderstandings |
| Find a screenshot using text inside it | Query attempts; preview openings; successful retrieval | Correct result recognized with fewer unnecessary previews |
| Fill five fields with Stack | Order errors; extra paste actions; recovery time | Predictable order and recovery without rebuilding the queue |
| Edit once and reuse the original afterward | Accidental saves; ability to find the original | Temporary changes do not damage historical content |
| Remove and restore a synthetic saved clip | Scope prediction; undo success; membership preservation | User expectations match removal and restoration |

Measure destination success only through the controlled exercise or direct observation. Clipboard staging and synthesized paste events are proxy signals. Any optional instrumentation must follow [the analytics policy](analytics.md), use permitted metadata only, and respect opt-out; do not collect content, search terms, or destination text.

## Implementation record

### UX-01–UX-03 — September 8, 2026

Implementation is complete in source. The table deliberately remains **Implemented — verification pending** because a signed installation and synthetic rendering cannot establish all cross-app interaction criteria.

**Delivered behavior and decisions**

- Direct Paste and Copy Only each apply consistently to double-click, Return, and Command–1…9. Direct Paste is the default for all installations, including upgrades; obsolete Classic values normalize to Direct Paste. An explicitly saved Copy Only choice survives future launches. Single-click and Space remain selection/preview actions. Shift–Return remains explicit plain-text paste.
- Added a General settings selector. The main panel retains its original layout, 320-point height, hover icons, and transient toolbar status; no footer or persistent shortcut hint is added. Explicit Copy keeps the panel open. Multi-selection copy now asks for one item instead of silently discarding the rest; combined copy remains UX-06 work.
- Added an Accessibility explanation and settings entry point. Permission is refreshed on app activation and before paste attempts. The unavailable-permission path copies a single clip, preserves the selection, and explains manual Command–V in a dismissible dialog with Return to App and Enable Direct Paste actions. Write failures show a dialog with Retry.
- Clipboard content is prepared before replacement. Missing/corrupt image payloads and missing file destinations are rejected before clearing the pasteboard. Successful writes still notify the capture-suppression callback; a failed replacement attempts to restore the previous snapshot.
- Direct paste checks destination identity and permission before each item. Recovery retains the pending selection and browsing context. Successful feedback says a paste request was sent, without claiming destination acceptance.
- Added scope-specific removal actions that name the folder, a confirmed Delete Everywhere… action, and Undo in a three-second toast plus the existing app menu / Command–Z. The toast pauses on hover, resumes its remaining duration on exit, and floats 12 points above the unchanged panel in a non-key child window. Native Clear Liquid Glass with bright text and localized dimming is used on macOS 26+, with a dark HUD-material fallback; a short message fits a 44-point capsule and a long message wraps into a 56-point rounded rectangle. The toast follows its parent window, clamps to the visible screen, and closes with the timeline. Undo clicks are excluded from outside-click dismissal. Undo has a padded 32-point hit target, a hover highlight, and pressed-state feedback on macOS 15+, with native borderless feedback on macOS 14. First-click events are explicitly enabled and the material ignores hit testing; Reduce Motion removes scaling and animated state changes. The toast does not add a window shadow. See [toast design research](toast-design-research.md) for sources, material tradeoffs, and the distinction between verified APIs and closed-source app internals. Consecutive removals replace the toast; Undo is tied to the matching removal identity and disappears when that identity is no longer available. Successful undo receives a fresh toast. Unpin and folder-submenu removal use the same feedback. Undo retains up to 20 detached snapshots for 30 seconds each in the running session, restores membership and order, avoids duplicates after recopy, and protects attachment paths against concurrent blob pruning. The snapshot lifetime ends on expiry, restart, or confirmed bulk cleanup. Delete Everywhere invalidates related undo entries while retaining unrelated ones.
- Cleanup and shorter retention use a review sheet showing the affected count and saved-content scope. Cancelling does not apply the proposed retention change. Confirmation deletes only the reviewed IDs, preserves newly captured records, and rechecks saved membership when saved clips should be retained. Folder records survive bulk content cleanup.
- Updated all four README versions, the copy tutorial, and 42 localization keys across all nine supported languages. The screenshot renderer uses the same panel height as the production timeline.

**Automated verification**

- `swift test`: passed, 56 tests across 11 suites (the opt-in performance benchmark is disabled in the normal run).
- `swift build`: passed.
- Integration tests use temporary SwiftData stores, a dedicated preferences suite, and named pasteboards. They do not replace the user's clipboard or clear their real history.
- Covered primary-action migration/persistence, action resolution, missing-media write rejection, text/rich-text/image/file writes, plain-text conversion, suppression callback counts, removal scope, restoration order, attachment retention/expiry, recopy deduplication, reviewed-ID cleanup, saved-content exclusions, read-only retention previews, undo after folder deletion, and restoration without displacing new captures or new pins.
- Localization validation confirmed nine languages per new key, matching format placeholders, and unchanged existing translations.
- `git diff --check`: passed.

**Signed installation and remaining interaction checks**

- Packaged arm64 using `package-release.sh --variant arm64 --skip-notarize --skip-dmg` and installed at `/Applications/Paste It.app`, with a temporary backup of the previous app. Verified `Developer ID Application: Yipeng Zhang (6K42AAA3AH)` and launched the installed app (final CodeDirectory hash: `9748ca2a94eaf0b0ee614b1da2c357239ec71afe`). No version bump, release, database reset, or permission reset was performed.
- The local MCP renderer can now exercise a removal in its temporary history and include the real toast in the capture. The final signed build is checked with [a short-message capsule](product-experience-evidence/toast-glass.png) and [a long-folder-name toast](product-experience-evidence/toast-glass-long.png). These use synthetic records and leave main history and the clipboard untouched. The timeline remains 320 points high; captures expand only to include the separate toast window and its surrounding margin.
- Earlier Computer Use attempts timed out, and a prior run read the main timeline without modifying records. In this refinement, automatic approval review rejected a fresh accessibility-tree inspection because the real panel could expose private clipboard contents. The final native rendering uses a separate synthetic backdrop window to exclude unrelated desktop content and compare dark, white, and colored backgrounds. No live pointer test was completed. Automated checks exercise the displayed toast callback and verify restoration in a temporary store; these do not substitute for a real mouse click.
- Still pending: clicking the primary-action selector; actual double-click / numeric / Return delivery and focus restoration; permission-denied and permission-return flows; active-Stack interaction; live toast Undo and hover timing, and destructive-confirmation cancellation; dark-appearance and accessibility-setting checks, plus long-label checks of the settings/confirmation layouts. No live deletion of user records was attempted. Keep the remaining acceptance boxes open until these checks can be performed.

**Next action:** finish the outstanding signed-app interaction checks for UX-01–UX-03 before marking them Done. UX-04 and later remain separate work items.
