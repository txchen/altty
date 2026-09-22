# AltTab recent updates: applicability to Altty

Follow-up: user authorized all recommended work; see [implementation and validation](implementation.md). The remainder records the pre-implementation assessment.

Reviewed 2026-09-22. Upstream baseline: v11.4.3 / `10af70aaaaac0a2dbb7d0aaa61cda21b065c203f`, recorded in the previous local research. Current upstream: v11.7.1 / `56891e0`. The range contains 107 commits and six subsequent releases: 11.4.4, 11.5.0, 11.6.0, 11.6.1, 11.7.0, 11.7.1. Verified against fetched Git history and [official releases](https://github.com/lwouis/alt-tab-macos/releases). Altty inspected at `a9efa07154451dd4dee596d3a1fe16a1650ce3ee` **plus the existing working-tree changes**, including mouse reversal.

This is source-based research, not a runtime bug reproduction or performance measurement. No production source was modified. Upstream commit counts include release, test, CI and documentation work; they are not counts of transferable features. Detailed upstream evidence is in [upstream-findings.md](upstream-findings.md).

## Decision

Six worthwhile work packages: **five implementation improvements and one validation package**. Prioritize Space-transition safety, bounded AX work, and refresh scheduling. Altty already implements several of the latest headline fixes, so copying the upstream subsystem would add complexity without equivalent benefit.

The existing [spec](../altty-window-switcher/spec.md) excludes copying AltTab implementation and requires independent implementation. Upstream publishes a [GPL v3 license](https://github.com/lwouis/alt-tab-macos/blob/56891e0/LICENCE.md). Recommendations below transfer observable behavior, scheduling requirements and regression scenarios into Altty's own architecture; they do not propose cherry-picking GPL source. No change to that product decision is needed to do this work.

## 1. P1: Invalidate stale Active Space state immediately

Upstream [767b96f](https://github.com/lwouis/alt-tab-macos/commit/767b96fcdb6984e4f7fdd84db870ab8b2a6494ad) separates immediate Space-topology facts from expensive settled window reconciliation. It fixes the old Space appearing briefly when the shortcut follows a Space transition. Its measured timings are upstream observations, not Altty results.

Local evidence: `AppDelegate.swift:459` only schedules `.replace`; `scheduleInventoryRefresh` waits 75 ms before querying, and inventory generation changes only when the resulting snapshot is applied. During that interval the cached prior-Space inventory remains present. Other focus/activation events may cancel an existing session, but do not establish that a newly invoked session cannot use old candidates.

Adaptation: mark the Active Space inventory invalid at the transition boundary and cancel the captured session immediately; rebuild through the settled query, accepting only the current transition token. Define shortcut behavior while the new inventory is unavailable. Preserve the ADR's Active-Space-only scope; there is no need for upstream cross-Space switching or topology fan-out. This is a concrete race to test, not a claim it was reproduced on hardware.

Acceptance: transition then shortcut at 0/25/50/75 ms cannot focus a previous-Space window; old snapshot/enrichment completions cannot repopulate it; test rapid successive Space changes.

## 2. P1: Bound AX concurrency and total work, with fairness between apps

Upstream [61978a8](https://github.com/lwouis/alt-tab-macos/commit/61978a83f36b16a4ab23eae5581a542250a5e12e), [8c8d283](https://github.com/lwouis/alt-tab-macos/commit/8c8d2836c8ee3de56253cec5e8efdc483711deb2), and the [current AX scheduler](https://github.com/lwouis/alt-tab-macos/blob/56891e0/src/macos/AXCallScheduler.swift) address stalled apps, per-process fairness and bounded traversal.

Local evidence: `AppDelegate.enrich` starts work per identity; `SystemAccessibilityAdapter.enrichment` uses `Task.detached` with synchronous AX reads. Inventory already deduplicates a given identity and retains a follow-up invalidation, but there is no explicit global/per-PID AX work limit. `AXWindowReader.windowElement` enumerates an app's windows for each requested WID, and the 250 ms timeout is per AX operation, not a total enrichment deadline. Thus many windows can still produce duplicate scans and a large amount of blocking work.

Adaptation: a small bounded executor, per-PID fairness, separate priority for focus prerequisites/readback, and one batch app-window lookup per discovery batch. Check an elapsed-time budget between synchronous calls; it cannot interrupt an AX call already executing. Preserve `.unavailable`/stale semantics and generation validation. Do not import cross-Space token brute-force scanning, periodic polling, or upstream pool sizes without measurements.

Acceptance: a stalled app with many windows cannot consume all capacity; healthy-app focus readback progresses; stopped/terminated generations discard queued work; verify actual AX call counts and latency on a helper app capable of delaying AX replies.

## 3. P1: Refresh scheduling must make progress during continuous events

Upstream [8c8d283](https://github.com/lwouis/alt-tab-macos/commit/8c8d2836c8ee3de56253cec5e8efdc483711deb2) coalesces event bursts, and [70fa760](https://github.com/lwouis/alt-tab-macos/commit/70fa760cb0f06f0e0768378fd1ac949d7808bd25) separates immediate model changes from scheduled work.

Local evidence: both `scheduleSemanticInvalidation` and `scheduleInventoryRefresh` cancel and restart a 75 ms sleep. Events arriving more frequently can postpone work until the burst stops. Snapshot queries themselves run in a detached task: cancelling the outer task rejects an old result but does not stop an already-running synchronous query. Stale-result safety is already present; bounded resource usage and bounded time to progress are separate requirements.

Adaptation: at most one snapshot query in flight, one merged pending request, a maximum wait during continuous events, and latest-state semantic reads. Keep `.replace` stronger than `.reconcile` until successfully applied; cancellation after taking a pending replacement must not lose the transition intent. This is an independent scheduling design, not reuse of upstream throttle code.

Acceptance: sustained 100 events/sec still produces bounded, timely accepted updates; no overlapping physical snapshot queries; last title wins; stop/restart and Space replacement retain correct sequence ownership.

## 4. P2: Strengthen process admission and stable identity handling

Upstream [4c49801](https://github.com/lwouis/alt-tab-macos/commit/4c49801f4e24e5f3b02ded4a2f01cf6f321da9e3) checks process liveness before admission to prevent short-lived helpers accumulating; [c96702a](https://github.com/lwouis/alt-tab-macos/commit/c96702ae4af09c02b30470825c79b6ac64807894) preserves discovered process identity when `NSRunningApplication` no longer reports it. The related [db7e21b](https://github.com/lwouis/alt-tab-macos/commit/db7e21bfd17fc6a0bf6ca61025f412ad707eb96b) repairs cross-Space front-app restoration; that restoration behavior is outside Altty's scope.

Local evidence: Workspace snapshots map running applications directly, and notification handling reads `application.processIdentifier` at handling time. Observer admission checks positive PID and registration token, but does not explicitly recheck process liveness. Altty already removes observers on termination and uses registration tokens to reject obsolete callbacks, so it does **not** need a rewrite and the exact upstream leak is not demonstrated here.

Adaptation: validate liveness at asynchronous admission boundaries; retain stable identity where a later notification can lack PID; test launch/termination reordering and PID reuse. Do not add continuous process polling to solve an unproven leak.

## 5. P2: Update only changed list content

Upstream [70fa760](https://github.com/lwouis/alt-tab-macos/commit/70fa760cb0f06f0e0768378fd1ac949d7808bd25) batches structural rendering while preserving immediate committed selection; [02152d9](https://github.com/lwouis/alt-tab-macos/commit/02152d9e611a630883c44753646a2128bedd44ec) keeps selection/hover tied to window identity.

Local evidence: `SwitcherPanelController.update` always calls `tableView.reloadData()` and resizes, including selection-only changes. Altty already freezes session order and selects by `WindowIdentity`; upstream dynamic grid algorithms are unnecessary.

Adaptation: compare previous and next panel state; selection-only changes just select/scroll, text-only changes refresh affected rows, and structural changes update layout. Preserve immediate release/click semantics; do not introduce upstream's adaptive 200 ms repaint delay by default in this small title-list UI.

Acceptance: repeated navigation performs no structural reload; destroyed selected row advances correctly; hover/click around row removal cannot address another WID. Measure before claiming CPU savings.

## 6. Cross-cutting: Bring over regression scenarios and fault-injection ideas

Upstream [95fd3e1](https://github.com/lwouis/alt-tab-macos/commit/95fd3e1154eec70c64ee54d86a7082e4d436dc5d) includes a debug-only refused-focus injection, and [e63c9ce](https://github.com/lwouis/alt-tab-macos/commit/e63c9ce) adds visual regression coverage. Recreate the scenarios independently within Altty's existing fixtures; do not copy tests or enable production control endpoints.

Useful scenarios: refused focus; late focus answer after a newer transaction; continuous title churn; delayed AX replies from one app; delayed snapshot completion across Space changes; terminate-before-observer-admission; repeated create/destroy cycles; list interaction while selected window closes. Pair deterministic adapter tests with a real-app soak and basic panel visual checks. Existing tests and performance budgets are a foundation, not missing work to duplicate.

## Already substantially covered

- **Only update MRU after confirmed focus** ([95fd3e1](https://github.com/lwouis/alt-tab-macos/commit/95fd3e1154eec70c64ee54d86a7082e4d436dc5d)): Altty verifies focused WID/PID before applying `.focused`, and guards asynchronous completions by transaction ID. Add the refused-focus scenario only where coverage is absent.
- **Stable selection while windows change** ([02152d9](https://github.com/lwouis/alt-tab-macos/commit/02152d9e611a630883c44753646a2128bedd44ec)): frozen session candidates, identity-based selection and separate authoritative liveness already address the core requirement.
- **Latest title after a burst** ([b47b52f](https://github.com/lwouis/alt-tab-macos/commit/b47b52f0e24c7c0846b6d6751628ca1a5625beba)): upstream fixed a throttle retaining an early closure payload. Altty rereads AX after debounce and retains a follow-up invalidation during enrichment. The corresponding concern here is continuous-event starvation, not that same stale-payload bug; the upstream commit is not evidence for adding a CG title fallback.
- **Observer cleanup / obsolete callbacks**: current dedicated observation worker, termination cleanup and registration tokens already cover the basic mechanisms. Process admission remains a narrower follow-up.

## Deliberately exclude

Capture/thumbnail/preview caches, ScreenCaptureKit discovery, Dock badges, native-tab grouping and brute-force cross-Space AX acquisition, windowless app placeholders, Pro/trial/license UI, gesture-trigger configuration and automatic updater changes do not serve Altty's current product scope. Cross-Space switching would conflict with ADR-0001; it should not be smuggled in as a bug fix.

Recommended sequence: combine packages 1–3 as the first reliability/performance change set, add their targeted tests from package 6, then handle packages 4–5 after reproductions or measurements. This report authorizes no claim of hardware validation: the production implementation, tests, benchmarks and release checks have not been run or changed in this research task.
