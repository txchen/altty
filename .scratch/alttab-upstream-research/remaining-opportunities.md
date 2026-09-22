# Remaining AltTab lessons after 37a8ace

2026-09-22. Compared current Altty `37a8ace` with the previously fetched AltTab
v11.7.1 / `56891e08861e2d43fafb31d58a4c7fd9ba2289ec`. This is a deeper pass over
the same pinned upstream version, not a claim that new upstream releases were
fetched. The previous five implementation packages are complete; these are
additional opportunities. No product source changed in this follow-up.

## 1. High: preserve physical shortcut gesture order

Upstream [5988133](https://github.com/lwouis/alt-tab-macos/commit/598813320177c9e1ffdc52eecfe10d18e5a69f7c)
addresses Carbon hotkey callbacks and modifier-release callbacks arriving out of
physical order after main-thread stalls. It records only relevant physical
shortcut events and matches each delayed callback to its own release, excluding
auto-repeat and unrelated typing.

Altty `SystemInputAdapter.modifiersChanged` drops releases while
`shortcutIsActive == false`; a later `hotKeyPressed` starts a session with no
remembered release. Current Space revisions and serial engine invocations do not
solve this earlier input-layer ordering problem.

Ran [InputOrderProbe.swift](probes/InputOrderProbe.swift) against the compiled
Altty debug objects, with fake registrations and system monitors disabled:

```
release-before-hotkey: eventCount=1, confirmationEmitted=false
after another release: confirmationEmitted=true
```

This confirms behavior under injected callback order. It does not show how often
macOS produces that order on this computer. First extend the input model/tests to
represent timestamps/gesture identity, then use controlled main-thread stalls to
verify real event delivery. Avoid a global typing log or a full upstream focus
repair system; Altty's focus serialization differs.

## 2. High: qualify real user windows using more than AX role

Upstream's current classifier is
[WindowAdmissionResolver](https://github.com/lwouis/alt-tab-macos/blob/56891e08861e2d43fafb31d58a4c7fd9ba2289ec/src/switcher/state/WindowAdmissionResolver.swift),
with [regression examples](https://github.com/lwouis/alt-tab-macos/blob/56891e08861e2d43fafb31d58a4c7fd9ba2289ec/src/switcher/state/WindowAdmissionResolverTests.swift).
It considers parent relationships, window level, size, AXMain, fullscreen and
semantics. Tests include rejecting a ChatGPT dictation strip and non-main floating
standard windows, while accepting PowerPoint slideshow and some Steam custom
windows. These are upstream fixtures, not locally reproduced application cases.

Altty's `WindowServerWindow` stores only WID/PID/order; qualification uses AXWindow
and four transient subroles. A synthetic call currently reports
`AXFloatingWindow classified transient: false`. More context is needed before
declaring every such window an unwanted target.

Build a compatibility fixture matrix for the user's apps; capture only the facts
needed to distinguish real windows from panels, and independently add narrow
rules. Do not blanket-reject nonzero levels, unknown subroles or whole apps.
Passwords/XPC helpers and Android Emulator are useful discovery cases to verify,
but should not receive speculative exceptions without a failure.

## 3. Medium-high: recover from transient AX failure, with a finite retry budget

Upstream [61978a8](https://github.com/lwouis/alt-tab-macos/commit/61978a83f36b16a4ab23eae5581a542250a5e12e)
and its [AX scheduler](https://github.com/lwouis/alt-tab-macos/blob/56891e08861e2d43fafb31d58a4c7fd9ba2289ec/src/macos/AXCallScheduler.swift)
separate timed-out apps and retry with backoff. The previous Altty change adopted
concurrency bounds and fairness, not that entire retry/quarantine policy.

Altty currently collapses failed AX reads to unavailable fields. After an
unavailable semantic result, an unchanged WindowServer reconciliation does not
request enrichment again. [AXRecoveryProbe.swift](probes/AXRecoveryProbe.swift)
confirmed this with a synthetic engine trace:

```
after unavailable AX + unchanged WS reconciliation: windows=0, effects=0
```

If a briefly unresponsive app recovers without another relevant AX notification,
its window can remain absent. Preserve failure categories first: timeout is not
unsupported attribute, invalid element or terminated process. For transient
failure only, permit a few bounded retries, releasing all capacity during backoff
and invalidating on Space/process/monitoring changes. Keep qualified-window
failure closed. Avoid permanent idle polling or blindly copying upstream delays.

## 4. Medium: pixel-level regression and real-application failure fixtures

Upstream [visual regression work](https://github.com/lwouis/alt-tab-macos/commit/e63c9ce6fd195272a4dfd4c13938d8ead527fae5)
and [QaSurfaces](https://github.com/lwouis/alt-tab-macos/blob/56891e08861e2d43fafb31d58a4c7fd9ba2289ec/src/debug/QaSurfaces.swift)
freeze dynamic content/animation, align backing pixels and wait for rendering
before comparison. Altty tests assert semantic content, geometry and view reuse;
they do not provide stored screenshot baselines or a real stalled AX provider.

Useful small matrix: long/CJK titles, dense lists and scrolling, disappearance of
the selected window, light/dark appearances, display scaling, settings/exception
screens. Use QA-only local snapshots, not product thumbnails or a production
control server. Add a disposable helper app for reproducible AX stalls and window
churn, then run the already-documented CPU/RSS acceptance procedure.

## Priorities and scope

First address input ordering and finite recovery, because the synthetic probes
already isolate concrete behavior; investigate qualification against real app
fixtures alongside that. Visual baselines and a real helper app deepen validation.
These are independent implementations under existing product constraints.
Cross-Space switching, individual native tabs, thumbnails/previews, windowless
placeholders and Pro UI remain product expansions, not automatic next steps.

Both probes link the existing `.build/arm64-apple-macosx/debug/Altty.build/*.swift.o`
and use no live hotkey registrations, event taps or AX queries. Their outputs
cannot establish physical keyboard timing or real app compatibility.
