Status: resolved
Type: grilling
Parent: ../map.md
Blocked by: 06, 07

## Question

What concrete functional, failure, performance, compatibility, permission and release acceptance matrix must the implementation-ready specification require, and which deterministic fixtures versus real-macOS smoke tests prove each behavior without making CI change the user's focus?

## Comments

### 2026-07-13 — Functional acceptance matrix accepted

Cover All-Windows and Current-App filtering over one global MRU; quick tap before panel display; delayed panel, forward/reverse wrap, cancellation, modifier confirmation and mouse interaction; stable sessions under create/destroy; minimized and hidden-app candidates; fullscreen Active Space while excluding inactive Spaces; exact/prefix Exceptions with independent Hide/Ignore union; atomic shortcut conflict handling; permission revocation and SkyLight fail-closed behavior; verified specific-WID focus before MRU promotion; settings save/recovery/migration; and the complete menu-bar/Settings/About/update UI. Prove pure ordering/filter/session/settings policy deterministically. Exercise real shortcuts, AX, SkyLight focus, fullscreen, TCC and UI through explicitly initiated macOS smoke tests.

### 2026-07-13 — Failure and race matrix accepted

Cover session/target closure, WID reuse, stale/rebuilt/timed-out AX elements, missing AX fields, process exit/hang, unavailable/failing SkyLight, false-success focus postconditions, focus-event reordering, permission revocation at every phase, shortcut/event-tap failure, generation rebuild during a session, absent/corrupt/future/interrupted settings migration, duplicate/lost/burst events, sleep/wake reconstruction and rapid cross-mode input. Every case must avoid crash, unhandled shortcut capture, false success and incorrect MRU promotion; end or cancel safely, expose recovery or fail closed, and never log titles or user content. Prove deterministic cases with fake adapters/clocks and replayable traces; reserve real TCC, WindowServer, sleep/wake and event-tap behavior for explicit smoke tests.

### 2026-07-13 — Performance acceptance accepted

Measure an authorized arm64 Release build on supported macOS. Over a five-minute idle run require under 0.2% average CPU, under 50 MB resident memory, no unexplained growth, zero polling and no uncaused AX/SkyLight calls. With warm cache require shortcut-to-focus-start p95 under 30 ms, panel presentation in the 100–150 ms window, and 100-window filter/sort/snapshot p95 under 10 ms. After 1,000 create/destroy events and 100 rapid switches, resources and registrations return to baseline with correct MRU. A 100-events/second burst for ten seconds must coalesce without linear AX amplification or main-thread stalls. Record hardware, OS, SHA, wakeups, call counts and p50/p95/p99. CI guards deterministic microbenchmarks; clean RC hardware measures real CPU and end-to-end behavior.

### 2026-07-13 — Compatibility policy accepted

Declare support only for actually tested macOS majors: always cover the latest patch of minimum macOS 15 and each advertised major, and run the complete private capability/focus matrix on a new major beta/RC before adding it. Cover at least an M1 baseline and a newer Apple-silicon Mac; ordinary, minimized, hidden-app, same-app multi-window, fullscreen Active Space, multi-display and Stage Manager states; ANSI/non-ANSI layouts and Option/Shift behavior; Finder, Safari, Terminal, System Settings, an Electron app and a nonstandard-window app. Run read-only SkyLight smoke after security updates and explicit focus smoke before support. Fail closed on capability, never infer support from version alone.

### 2026-07-13 — Accessibility lifecycle accepted

Cover clean/no trust, user grant, denial without repeated prompts, explicit retry, runtime revocation, regrant without restart, inventory/observer reconstruction, signed patch/minor upgrade, direct ZIP and Homebrew install/upgrade/cross-replacement, move out/back to `/Applications`, distinct dev/release identities, changed designated requirement, sleep/wake and OS update. Never edit TCC on uninstall or zap. Only user action prompts; while untrusted keep menu/Settings available but unregister both shortcuts and release observers. Regrant restores operation without restart. Logs contain permission-state transitions only. Final signed upgrade/install cases remain release gates until the organization identity exists.

### 2026-07-13 — Release-candidate gate accepted

Require arm64/macOS 15 deployment, correct nested Developer ID signing, hardened runtime, timestamp, approved entitlements only, strict codesign and Gatekeeper success, accepted notarization plus staple, clean final-ZIP revalidation and quarantine-origin launch. Checksums must match release and Cask; direct/Homebrew install, upgrade, uninstall and zap must pass; identity/version/about/release notes must agree; artifacts must exclude tests, debug symbols, secrets and CI residue. Link every functional, failure, performance, compatibility and TCC result to the build SHA. A failed workflow cannot publish a GitHub Release or tap update. Only a fully passing RC may become stable.

## Answer

Acceptance is a layered matrix. Deterministic tests run continuously without changing the user's desktop; explicit macOS smoke tests exercise system behavior; formal signed release gates run only against an approved release candidate.

### Deterministic functional coverage

- Prove All-Windows and Current-App filtering over one global MRU, including invocation PID snapshotting.
- Prove quick-tap switching before panel presentation; delayed panel, forward/reverse wrap, modifier confirmation, Escape cancellation and mouse interaction.
- Prove stable session snapshots: new windows wait, destroyed windows disappear and selection advances safely.
- Prove minimized/hidden-app eligibility on the Active Space, fullscreen Active Space behavior and exclusion of inactive Spaces.
- Prove exact/prefix Exceptions, independent Hide/Ignore semantics and rule union.
- Prove atomic shortcut replacement/conflict rollback, settings save/corrupt recovery/sequential migration, and every menu/Settings/About/update action.
- Prove that only verified specific-WID focus promotes MRU; missing Accessibility or SkyLight capability unregisters shortcuts and remains recoverable through UI.

Use pure policy tests for ordering/filtering/session/settings behavior. Inject fake SkyLight, AX, workspace and clock adapters for orchestration. Keep replayable event traces free of titles and user content.

### Failure and race coverage

Cover candidate/target closure, WID reuse, stale/rebuilt/timed-out AX elements, missing AX fields, process exit/hang, SkyLight load/query/focus failure, false-success postconditions, external/internal focus-event reordering, permission revocation in every phase, shortcut/event-tap failure, generation rebuild during a session, absent/corrupt/future/interrupted settings, duplicate/lost/burst events, sleep/wake reconstruction and rapid cross-mode input.

Every failure must avoid crash, unhandled shortcut capture, false success and incorrect MRU. It must safely finish/cancel, expose recovery or fail closed, and emit no private user content. Reserve real TCC, WindowServer focus, sleep/wake and event-tap assertions for explicitly initiated smoke tests.

### Performance coverage

On an authorized arm64 Release build:

- Five-minute idle average CPU is below 0.2%; resident memory is below 50 MB with no unexplained growth, polling or uncaused AX/SkyLight calls.
- Warm-cache shortcut-to-focus-start p95 is below 30 ms; panel presentation remains within 100–150 ms.
- Filtering, sorting and snapshotting 100 windows has p95 below 10 ms.
- After 1,000 create/destroy events and 100 rapid switches, resources, registrations and MRU remain correct and return to baseline.
- A ten-second 100-events/second burst coalesces without linear AX amplification or main-thread stalls.

Record hardware, OS, build SHA, wakeups, adapter call counts and p50/p95/p99. CI enforces deterministic microbenchmarks; clean RC hardware measures real resource and end-to-end results.

### Compatibility and application matrix

Support only actually tested macOS majors: the latest patch of minimum macOS 15 plus each advertised major. Test a new major beta/RC before adding support. Cover an M1 baseline and newer Apple silicon, ordinary/minimized/hidden/multi-window/fullscreen windows, multiple displays, Stage Manager, ANSI/non-ANSI layouts and Option/Shift behavior. Smoke Finder, Safari, Terminal, System Settings, an Electron app and a nonstandard-window app. Run read-only SkyLight smoke after OS security updates and explicit focus smoke before support; never infer compatibility from a version number.

### Accessibility and install lifecycle

Test clean trust, grant, denial, explicit retry, runtime revocation, regrant without restart, observer/inventory reconstruction, signed upgrade, direct ZIP, Homebrew install/upgrade/cross-replacement, app movement, separate dev/release identities, changed designated requirement, sleep/wake and OS update. Only user action prompts. While untrusted, keep menu/Settings available but unregister shortcuts and release observers. Never edit TCC during uninstall or zap. Final signed lifecycle cases remain release gates until the organization identity exists.

### Release-candidate acceptance

Require arm64 with macOS 15 deployment target; correct nested Developer ID signing; hardened runtime and secure timestamp; no sandbox, `get-task-allow`, disable-library-validation or unapproved entitlement; strict codesign/Gatekeeper success; accepted notarization and staple; post-ZIP validation and quarantine-origin launch. Verify checksums against GitHub/Cask, direct and Homebrew lifecycle, stable identity/version metadata, About/release notes consistency and absence of secrets, test assets, debug symbols or CI residue. Attach every result to the build SHA. Any failure blocks GitHub Release creation and tap update.
