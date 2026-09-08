# SwiftUI performance review and optimization record

## Scope

This review covers the timeline, search, clipboard ingestion, media previews and history storage. The initial findings are based on source inspection, not an Instruments recording. Improvements must preserve clipboard suppression, selection, focus, persistence and the macOS 14 deployment target.

Existing strengths include lazy card creation, local hover state, search debounce, normalized search caching, ImageIO thumbnails, background OCR and panel prewarming.

## Ordered implementation plan

| Order | Finding | Feasible implementation | Verification |
| --- | --- | --- | --- |
| 1 | `ClipItem.previewText` imports HTML/RTF even when plain text wins; cards read it repeatedly. Quick preview parses in both initialization and its task. | Short-circuit plain text; cache resolved card summaries and full character counts by content; bound highlighting; initialize rich preview once. | Plain/rich fallback regression tests, Unicode summary tests, rich card and edit smoke checks. |
| 2 | Tab changes append six records per published update (834 appends for 5,000 results); changing the scroll view identity remounts cards. | Publish results once and retain scroll view identity while resetting its native scroll offset. | Large-result publication checks, rapid tab changes, horizontal scroll and reopen with leading inset. |
| 3 | Root views observe broad state; published array mutations and manual history notifications duplicate work. | Coalesce history processing, narrow list dependencies, avoid selection-count scans and no-op state writes. | Selection, pin/unpin, deletion and metadata refresh checks. |
| 4 | Search and filter counts run synchronously on MainActor after debounce/yield. | Search immutable Sendable documents off-main, cancel stale work and validate request revisions before applying results. | Search semantics, cancellation, history changes during search and synthetic scale benchmarks. |
| 5 | Full-image preview reads synchronously; image loading does not explicitly downsample; link metadata retains unbounded image bytes. | Async size-aware ImageIO decode; pixel-based costs; bounded metadata cache/downloads/concurrency; async metadata blob writes. | Image decode/cache tests and signed image/link preview checks. |
| 6 | Startup eagerly folds all search text; expiration removal is quadratic; ingestion reads both PNG and TIFF. | Build search normalization lazily/off-main, use an expired-ID set, read TIFF only as fallback. | Synthetic history/search tests, ingestion regression checks and signed restart. |

Large-scale storage pagination, a database full-text index, wholesale Observation migration and replacement with NSCollectionView are conditional follow-ups. They require measurements showing that the simpler changes above are insufficient. Avoid speculative model migrations or changes to rendering style.

## Design constraints

- SwiftData models and their ModelContext stay on their owning actor. Only immutable values cross actors.
- AppKit HTML importing is not a generic background-safe parser. Avoid redundant imports and keep full-fidelity HTML rendering on the main actor.
- Cache keys include content or media versions. Editing must invalidate display data without losing an active edit.
- Lazy layout reduces view creation; it does not eliminate collection publication and diffing costs. Task.yield is not a frame boundary.
- Keep the first card's natural leading inset when resetting scroll position.
- Use only synthetic clipboard content in tests. Do not reset the user's database or permissions.

## Validation protocol

1. Run focused Swift Testing regressions, then `swift test` and `swift build`.
2. Benchmark synthetic 500, 5,000 and 20,000-record search workloads; report environment and measured results without extrapolating to frame rates.
3. Package with `./scripts/package-release.sh --variant arm64 --skip-notarize --skip-dmg`.
4. Verify the Developer ID signature before replacing `/Applications/Paste It.app`; launch and verify the installed signature.
5. Exercise capture, search/filter, selection, scrolling/reset, Space preview, editing and cross-app paste as applicable. Record pass/fail and any permission/environment limitation explicitly.
6. Run `git diff --check` and inspect the final scope.

For future Instruments profiling, measure panel time to interaction, SwiftUI body updates, main-thread CPU, scrolling hitches and peak/resident memory on the same machine and synthetic dataset before and after each change.

## References

- [Apple: Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Apple: Migrating to Observation](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [Apple: NSAttributedString HTML import constraints](https://developer.apple.com/documentation/foundation/nsattributedstring/init(fileurl:options:documentattributes:))
- [Apple: ImageIO thumbnail creation](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:))

## Implementation and validation results

Implemented on September 8, 2026. The repository was clean before this work. No database schema, application version, signing identity or user preference was changed by the implementation.

### Completed changes

1. **Text:** Rich fallback is an autoclosure, so usable plain text never imports HTML/RTF. A bounded 240-entry card cache stores 1,024-grapheme summaries and full UTF-16 character counts. Text highlighting uses indices from the original string, supports case/diacritic-insensitive matching, and has an equality boundary to reuse unchanged rendering. Rich preview imports once per mounted item rather than once in both initialization and its task.
2. **List publication and identity:** A tab change publishes at most an empty transition and one complete result, rather than appending six records at a time. A native scroll-offset reset preserves the lazy strip's identity and its 18-point card inset. The list has an explicit equality boundary keyed by list version, selection, query, scroll request, history revision and tab.
3. **Notifications:** History changes are coalesced per main-queue turn and distinguish structural changes from individual content changes. Content-only changes do not invalidate unfiltered membership caches. Selection counts no longer scan all results, and unchanged selections/results avoid redundant assignments. Structural refreshes preserve the browsing order while applying additions and removals.
4. **Search:** An actor searches immutable value snapshots and caches normalization/classification. Work checks cancellation every 64 documents; MainActor verifies the request generation, tab and filter key before applying IDs. Filter counts also run on the actor. The simple prefix-string narrowing shortcut was removed because partially typed query operators can change semantics; exact per-tab result caching remains. Synthetic render now awaits the actual search task instead of assuming a fixed sleep is sufficient.
5. **Media:** Async ImageIO decoding uses 720-pixel card and 1,600-pixel preview bounds, with decoded-byte cache costs and in-flight invalidation tokens. Quick preview loads asynchronously and reports a missing image after a failed load. Link requests have four active fetch slots, streaming limits of 2 MiB for HTML and 8 MiB per image, at most three icon candidates, and a 64-entry/24 MiB LRU value cache. New link previews are downsampled and written off-main. HTML entity import stays on MainActor.
6. **Ingestion and storage:** Startup no longer eagerly folds all history text. Expiration and bulk-clear membership use ID sets. PNG success skips TIFF retrieval. A newer clipboard change count is not consumed while another snapshot is being normalized. Rich-only clipboard fallback imports on MainActor once, while thumbnail/hash/blob work remains outside it.

The implementation uses focused dependency boundaries rather than a wholesale `@Observable` migration. Initial SwiftData fetch still loads history, and first-screen database pagination remains a measured follow-up. Existing synchronous image helpers remain for non-card callers; the modified card and quick-preview loading paths use async decode.

### Automated validation

- `swift test`: **passed, 33 tests across 7 suites**, including the opt-in benchmark suite reported as skipped in the normal run.
- Added regression coverage for lazy rich fallback, Unicode summary boundaries, search order/operators/accents, changed-content cache invalidation, cancellation, cache eviction/oversize rejection and image downsampling.
- Added a separate application integration target with ephemeral SwiftData stores. It verifies one notification for a multi-mutation promotion, at most two result publications for a 40-item tab, latest-query wins, search clearing, edits affecting search, summary invalidation and deletion selection cleanup.
- `swift build`: **passed**.
- Developer ID arm64 packaging with `--skip-notarize --skip-dmg`: **passed**.
- `git diff --check`: **passed**.
- Existing SwiftPM resource and deprecated screen-capture warnings remain; they did not fail compilation or tests.

### Release search measurements

Environment: Apple M3 Pro, macOS 26.6.2, arm64, Swift tools 6.2 / Xcode SDK 26.2. Synthetic records contain a short Unicode title and approximately 240 characters of searchable text. Cold timing includes normalization/classification; warm timing is the total for ten repeated searches divided by ten. Each query matches all records. These measurements exclude SwiftData snapshot creation, SwiftUI layout and screen rendering.

Command:

```sh
PASTEIT_PERFORMANCE_BENCHMARKS=1 swift test -c release --filter PerformanceBenchmarks
```

| Records | Cold search | Mean warm search (10 runs) |
| ---: | ---: | ---: |
| 500 | 5.30 ms | 0.60 ms |
| 5,000 | 24.84 ms | 6.61 ms |
| 20,000 | 101.71 ms | 29.76 ms |

These are post-change measurements, not a before/after speedup claim or a frame-rate claim. A full Instruments comparison remains future work.

### Signed installation and runtime checks

The final application was installed at `/Applications/Paste It.app`, launched, and its signature verified with `codesign --verify --deep --strict` and `codesign -dv --verbose=4`. The authority is **Developer ID Application: Yipeng Zhang (6K42AAA3AH)**. Notarization was intentionally skipped for local verification. Previous application bundles were retained in temporary backups; the user's history and preferences were not reset.

The already-enabled loopback MCP service was used without changing its preference. All rendering requests used ephemeral history. A temporary HTTP server bound only to 127.0.0.1 supplied synthetic link metadata and images, and was stopped after validation.

| Scenario | Result and evidence |
| --- | --- |
| Mixed text, rich payload, Unicode, number and image cards | Passed on the final signed build. [Screenshot](performance-evidence/mixed.png) |
| Long text summary and full character footer | Passed: bounded card text retained a 7,232-character footer. [Screenshot](performance-evidence/mixed.png) |
| Search and highlighting | Passed: `cafe` matched and highlighted `café`, with only matching cards displayed. [Screenshot](performance-evidence/search.png) |
| Image filter and original dimensions | Passed: `type:image` displayed only the synthetic 2,400 × 1,200 image. [Screenshot](performance-evidence/filter.png) |
| Link download, entity decoding, thumbnail write/load and search update | Passed against the temporary local server; fetched title and preview appeared and matched the query. [Screenshot](performance-evidence/link.png) |
| Actual TextEdit capture and persistence | Passed: a synthetic bold TextEdit selection was captured as `richText`; a narrowly scoped MCP search after the final app restart returned that one synthetic record. |
| Application responsiveness | A one-second process sample found the main thread waiting normally for events. Observed footprint was 77.2 MiB with a 90.5 MiB peak; this was a single live-session observation, not a controlled memory benchmark. |
| Cross-app Return/Shift-Return paste, focus restoration, command-click multi-select, Space/Command-E preview/edit and repeated scroll/reopen | **Not fully verified.** Computer Use intermittently returned `timeoutReached`, ScreenCaptureKit error -3811, and state-change guards. Synthetic rendering and unit tests do not substitute for these interaction checks. |

Only synthetic screenshots are stored with this report. No raw clipboard dumps, process samples, private history or compiler logs were copied into the repository. One broad UI-state read was rejected by automatic approval review; subsequent reads were narrowed to synthetic content and control metadata.

### Remaining acceptance work

Reliable direct UI control is needed to complete the interaction row above, especially the native scroll reset and quick-preview focus/edit lifecycle. Also profile SwiftUI updates and hitches before attributing a user-visible speedup to individual changes. Full database pagination, FTS, wholesale Observation migration, and changes to glass rendering or the collection container remain optional follow-ups rather than unmeasured rewrites.
