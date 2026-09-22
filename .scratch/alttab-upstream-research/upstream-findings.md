# AltTab upstream findings — 2026-09-22

Live primary-source review of `lwouis/alt-tab-macos`, cloned at `56891e08861e2d43fafb31d58a4c7fd9ba2289ec` into `upstream/`. Read Altty CONTEXT.md and ADR 0001 first. No product code changed or upstream code incorporated.

## Scope and provenance

[Latest release v11.7.1](https://github.com/lwouis/alt-tab-macos/releases/tag/v11.7.1) is dated 2026-09-20; v11.7.0 is 2026-09-17. Prior Altty baseline `10af70aaaaac0a2dbb7d0aaa61cda21b065c203f` is v11.4.3 (2026-07-09). Actual git comparison yields **107 commits**, with **71 fix**, **8 perf**, **4 feat**, **4 refactor**, and **20 other** commits. There are **six subsequent releases**: 11.4.4 Aug 6, 11.5.0 Aug 19, 11.6.0 Sep 5, 11.6.1 Sep 11, 11.7.0 Sep 17, 11.7.1 Sep 20. These counts are commit categories, not independently portable improvements. [Compare](https://github.com/lwouis/alt-tab-macos/compare/v11.4.3...v11.7.1).

v11.0.0 introduced Pro on May 21, before both the recent 90-day window and the previous baseline. Native-tab grouping, capture/thumbnails, inactive-Space discovery, gestures and Pro licensing/UI account for substantial upstream complexity and do not automatically belong in Altty. Altty ADR deliberately restricts switching to the Active Space.

Caution: release 11.7.0 notes link some earlier hashes that are not ancestors in the current clone. Below links use verified current-history commits and actual inspected patches, rather than blindly repeating changelog hashes. Dates below are release dates; author dates can precede commit/publication dates.

## Verified changes and transferability

### Bounded AX work

2026-09-05 / 11.6.0 — [61978a8](https://github.com/lwouis/alt-tab-macos/commit/61978a83f36b16a4ab23eae5581a542250a5e12e). Actual scheduler patch caps each PID at 3 calls across isolated first-read, scan and retry pools; queued excess does not occupy workers. A timeout quarantines a PID until a successful response; expiration alone does not make it healthy. Failure/unknown differs from an authoritative empty result. Strong transferable principle; pool sizes are upstream policy, not recommended Altty constants.

### Burst and traversal budgets

2026-09-20 / 11.7.1 — [8c8d283](https://github.com/lwouis/alt-tab-macos/commit/8c8d2836c8ee3de56253cec5e8efdc483711deb2). Move/resize ingress coalesces per WID only within semantic segments; focus/order/lifecycle/Space edges preserve ordering. AX traversal receives a 250ms elapsed-time budget, checks before subsequent IPC, and resumes the first unfinished candidate. In-flight IPC is not forcibly cancelled. Incomplete tab reads stay unknown. Screenshot discovery expires and rejects late callbacks; screenshot portions do not apply without thumbnails.

### Separate model updates from structural repaint

2026-09-20 / 11.7.1 — [70fa760](https://github.com/lwouis/alt-tab-macos/commit/70fa760cb0f06f0e0768378fd1ac949d7808bd25). Discovery and AX results apply immediately; structural repaints coalesce with a cost-adaptive quiet period capped at 200ms. Committed focus stays immediate and supersedes queued repaint; selection resolves by identity while layout lags. Useful principle, but Altty already stabilizes session identity.

### Admission liveness

2026-09-20 / 11.7.1 — [4c49801](https://github.com/lwouis/alt-tab-macos/commit/4c49801f4e24e5f3b02ded4a2f01cf6f321da9e3). Delayed application admission now checks actual kernel process existence. NSRunningApplication.isTerminated could lag an already-processed removal, admitting a dead app forever with AX retries every 30 seconds. Patch explicitly handles nonpositive PID, EPERM and zombies. A precise lifecycle race, not a generic memory leak fix.

### Retain process identity

2026-09-20 / 11.7.1 — [c96702a](https://github.com/lwouis/alt-tab-macos/commit/c96702ae4af09c02b30470825c79b6ac64807894). Keep the PID learned via WindowServer even when NSRunningApplication stops reporting it; use tracked identity for activation, hide/show and cleanup. This is separate from window-ID generation tracking.

### Space transition leading/trailing separation

2026-08-06 / 11.4.4 — [767b96f](https://github.com/lwouis/alt-tab-macos/commit/767b96fcdb6984e4f7fdd84db870ab8b2a6494ad). Actual patch refreshes cheap Space topology on leading event, leaves membership and expensive queries for trailing settle, and rereads topology during switcher show if a transition is in flight. Leading topology update deliberately does not repaint, to avoid consuming the UI throttle edge before the real focus event. Upstream measured ~273ms stale topology before versus ~3ms after; these are author measurements, not measurements on Altty.

### Observe focus rather than assume it

2026-09-20 / 11.7.1 — [95fd3e1](https://github.com/lwouis/alt-tab-macos/commit/95fd3e1154eec70c64ee54d86a7082e4d436dc5d). Only actual observed destination focus updates ordering. Activation arriving before focused-window answer must wait rather than reuse old focus. Compare to Altty verified focus commit before proposing work.

### Restore previous Space app via tracked PID

2026-09-20 / 11.7.1 — [db7e21b](https://github.com/lwouis/alt-tab-macos/commit/db7e21bfd17fc6a0bf6ca61025f412ad707eb96b). Device Hub provided no LaunchServices PID; use WindowServer-learned PID for restoring the source Space app. The cross-Space restore operation is outside Altty Active Space scope; identity lesson is shared with c96702a.

### Latest title throttle payload

2026-09-20 / 11.7.1 — [b47b52f](https://github.com/lwouis/alt-tab-macos/commit/b47b52f0e24c7c0846b6d6751628ca1a5625beba). Throttler now retains the newest pending title when many arrive. This is NOT a CGWindow title fallback change. Altty rereading actual title after debounce may already cover the behavior.

### Rapid gesture sequencing and fault injection

2026-09-17 / 11.7.0 — [5988133](https://github.com/lwouis/alt-tab-macos/commit/598813320177c9e1ffdc52eecfe10d18e5a69f7c). Passive key/modifier log pairs delayed Carbon hotkeys with the release after the matching physical press; ignores unrelated typing and auto-repeat. Intent registration precedes model update so an older overlapping focus repair cannot restore the previous target. Adds debug --qa-stall-main. Altty input pipeline differs; reproduce symptoms and transfer fault scenarios rather than import the Carbon workaround.

### Native shortcut interference

2026-09-17 / 11.7.0 — [ffc3cbe](https://github.com/lwouis/alt-tab-macos/commit/ffc3cbeacd48fe8f722919cd757521566e452b50). Upstream had disabled the wrong symbolic hotkey ID (force quit). Removes unnecessary disabling of move-focus-next-window. Audit only if Altty manipulates native symbolic hotkeys.

### Idle wakeups

2026-09-17 / 11.7.0 — [5d44068](https://github.com/lwouis/alt-tab-macos/commit/5d4406821209e2a0c2ab06df1b20639a47f2a8f6). Cancels successful capture watchdogs, adds slack for background/retry timers, fixes permission polling cadence transition from 5 seconds to 1 minute. Thumbnail watchdog detail is out of scope without captures; timer leeway is a general low-cost idea.

### Deterministic UI regression harness

2026-09-20 / 11.7.1 — [e63c9ce](https://github.com/lwouis/alt-tab-macos/commit/e63c9ce6fd195272a4dfd4c13938d8ead527fae5). DEBUG commands expose app surfaces, freeze volatile content/motion, wait for AppKit rendering, and keep local accepted references per display scale. Fault injection, semantic state snapshots and long-run process churn checks are useful independent tests; no claim these upstream tests validate Altty.

## Licensing and adoption boundary

At inspected HEAD, [LICENCE.md](https://github.com/lwouis/alt-tab-macos/blob/56891e08861e2d43fafb31d58a4c7fd9ba2289ec/LICENCE.md) contains GNU GPL version 3; it is unchanged from the prior baseline. `package.json` says MIT, but this metadata is not a reason to treat the application Swift source as permissively licensed. Existing Altty requirements call for independent implementation rather than GPL code copying. Findings therefore identify behavior, invariants, failure cases and experiments; they do not recommend cherry-picking upstream implementation.

## Verification limits

Reviewed release metadata, git history, relevant patch bodies and current scheduler code. No upstream app was built or run, and no performance claims were independently reproduced. Altty applicability and priority are in the companion local assessment from the parent task.
