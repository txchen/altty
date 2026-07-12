# AltTab window model research

## Scope and verdict

This is a source reading of the local AltTab checkout at `/Users/hibiki/code/github/alt-tab-macos`, pinned to commit `10af70aaaaac0a2dbb7d0aaa61cda21b065c203f`; it is not a proposal to copy its GPL implementation.

AltTab's current model is not “enumerate `kAXWindows` when the shortcut is pressed.” It maintains a long-lived, per-window model keyed chiefly by `CGWindowID`: SkyLight/WindowServer supplies the all-Space inventory, geometry, fullscreen state, Space membership, lifecycle, visibility and focus signals; Accessibility (AX) supplies a live window element, semantic qualification, title, minimized state, tab membership and the final raise action. The switcher hot path uses cached state, applies per-shortcut filters, sorts, and selects. This split is essential to mature cross-Space and tab behavior; none of it inherently requires screenshots.

For Altty's two modes, the essential product model is one shared inventory and MRU, with a mode predicate layered over it: Option-Tab admits all eligible windows; Option-Grave additionally requires the owner PID to equal the application that was active when the invocation began. Windowless-app placeholders are contrary to Altty's already-settled “selectable unit is a window” rule and should not be inherited by default.

## Discovery and identity

1. Startup records running applications, then observes app lifecycle. A regular app is represented even before a window is found ([Applications.swift:18](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:18), [Application.swift:70](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Application.swift:70)).
2. A refresh asks SkyLight for WIDs across every known Space, including invisible-tagged windows, batches WindowServer metadata, and initially keeps application-window-level candidates. It skips already tracked live WIDs and asynchronously acquires AX elements for new ones ([Applications.swift:91](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:91), [Applications.swift:99](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:99), [Applications.swift:107](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:107)).
3. There is no direct WID-to-AX-element API in this design. Acquisition first scans the owning application's `kAXWindows` (the cheap current-Space route), then uses a targeted remote-token brute-force route for other-Space windows ([WindowElementAcquisition.swift:3](/Users/hibiki/code/github/alt-tab-macos/src/windowserver/WindowElementAcquisition.swift:3), [WindowElementAcquisition.swift:9](/Users/hibiki/code/github/alt-tab-macos/src/windowserver/WindowElementAcquisition.swift:9)). A WindowServer entry with no live AX element is rejected as torn down or transient ([WindowDiscriminator.swift:60](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowDiscriminator.swift:60)).
4. A newly acquired element is read for AX title, role, subrole, main, minimized and children/tab group. Geometry, level and fullscreen come from the WindowServer snapshot; real Space membership is separately queried off-main ([Applications.swift:131](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:131), [Applications.swift:147](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:147), [Applications.swift:150](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:150)).
5. Identity is primarily `CGWindowID`, with AX-element equality as a fallback. A fresh AX element for the same WID rebinds the cached reference, handling apps that rebuild accessibility nodes without changing the WindowServer window ([Windows.swift:410](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:410)).

The implication for Altty is sharp: AX-only enumeration cannot deliver the claimed all-Space behavior. If cross-Space windows remain a requirement, the architecture must isolate a private SkyLight discovery adapter and keep an AX acquisition adapter beside it.

## Qualification: what becomes a switchable window

Qualification is deliberately staged:

- The cheap prefilter accepts application window level before AX acquisition ([WindowDiscriminator.swift:47](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowDiscriminator.swift:47)).
- The semantic filter rejects WID 0, missing geometry, and windows at or below 100×50; normally it requires `AXStandardWindow` or `AXDialog` ([WindowDiscriminator.swift:2](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowDiscriminator.swift:2), [WindowDiscriminator.swift:8](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowDiscriminator.swift:8), [WindowDiscriminator.swift:16](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowDiscriminator.swift:16), [WindowDiscriminator.swift:25](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowDiscriminator.swift:25)).
- A substantial app-specific compatibility table rescues nonstandard real windows and rejects known panels, tooltips and transient overlays. This is evidence that “role + minimum size” is a baseline, not a complete universal classifier; for example, Android Emulator empty-title transient dialogs are explicitly rejected ([WindowDiscriminator.swift:77](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowDiscriminator.swift:77), [WindowDiscriminator.swift:201](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowDiscriminator.swift:201)).

Altty should specify a conservative generic predicate first and treat app exceptions as data/compatibility patches backed by regression fixtures, not embed AltTab's historical table wholesale.

## Continuous tracking and MRU

Each accepted window is appended with a monotonically increasing creation order and an MRU rank (`lastFocusOrder`, zero is most recent), indexed by WID, and subscribed to WindowServer events ([Window.swift:39](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Window.swift:39), [Windows.swift:430](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:430)). Promoting a window moves it to rank zero and shifts only the windows formerly ahead of it ([Windows.swift:394](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:394)).

MRU is not driven by one signal. WindowServer focus events are primary; newly created or focus-before-discovery WIDs are remembered and promoted when appended ([Windows.swift:6](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:6), [Windows.swift:11](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:11), [Windows.swift:436](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:436)). A one-time AX focused-window read seeds a window discovered after its app was already frontmost ([Window.swift:440](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Window.swift:440)). App activation is a weak AX backstop, while activation/focus race suppression prevents raise storms or background refocuses from corrupting MRU (see the documented event handling at [WindowServerEvents.swift:293](/Users/hibiki/code/github/alt-tab-macos/src/events/WindowServerEvents.swift:293)). Tab switches need special treatment because they can emit Space-membership swaps without a focus event ([WindowServerEvents.swift:246](/Users/hibiki/code/github/alt-tab-macos/src/events/WindowServerEvents.swift:246)).

For Altty, one global window MRU should feed both modes. The current-app mode should filter that sequence, not maintain a second MRU, so its order remains “most recent among this app's windows.” The invocation must snapshot the frontmost PID before Altty activates its own panel.

## Edge cases

### Minimized and hidden

Minimized is an AX fact (`kAXMinimized`), not inferred from WindowServer ordered-out state, because ordered-out also covers closing, hidden apps and other Spaces ([Applications.swift:147](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:147), [Applications.swift:201](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:201)). App hidden state comes from `NSRunningApplication` initially and is kept live separately because it is AppKit state, not WindowServer state ([Application.swift:72](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Application.swift:72), [WindowServerEvents.swift:351](/Users/hibiki/code/github/alt-tab-macos/src/events/WindowServerEvents.swift:351)). Both remain legitimate inventory items and may be hidden or placed at the end by per-shortcut policy ([WindowFilterResolver.swift:34](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowFilterResolver.swift:34), [WindowOrderResolver.swift:37](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowOrderResolver.swift:37)). Focusing first clears AX minimized state ([Window.swift:281](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Window.swift:281)); process fronting then reveals a hidden owning app as part of normal activation.

### Other Spaces and fullscreen

Space topology and per-window membership are cached and refreshed off the show path; missing entries receive targeted per-WID backfill ([Applications.swift:60](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:60), [Applications.swift:69](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:69)). Fullscreen is derived from WindowServer state and reconciled on live window events and settled Space transitions, not from screenshots ([Applications.swift:201](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:201), [WindowServerEvents.swift:327](/Users/hibiki/code/github/alt-tab-macos/src/events/WindowServerEvents.swift:327)). Fullscreen is just another filterable window property.

### Native tabs

Inactive native tabs may have no Space membership and may not occur in normal CGS discovery. AltTab reads `AXTabGroup` children, matches sibling titles to tracked windows, and explicitly discovers untracked inactive tabs through AX ([TabGroup.swift:19](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/TabGroup.swift:19), [TabGroup.swift:111](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/TabGroup.swift:111), [TabGroup.swift:155](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/TabGroup.swift:155)). It also infers already-tracked fullscreen/tab-switch groups from same-app geometry when AX temporarily exposes no tab group, then mirrors the active tab's Space, fullscreen and minimized state to inactive siblings ([TabGroup.swift:34](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/TabGroup.swift:34), [TabGroup.swift:45](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/TabGroup.swift:45), [TabGroup.swift:58](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/TabGroup.swift:58)).

This needs an explicit Altty decision: is each native tab a selectable “window,” or only the active tab/window? Supporting every tab is materially more complex and changes identity, discovery, filtering and focus tests.

### Windowless applications

AltTab creates an icon-only placeholder for each regular, live application with no non-phantom real window; it removes the placeholder when a real window appears. Focusing it launches or activates the app ([Application.swift:127](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Application.swift:127), [Window.swift:255](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Window.swift:255)). Altty should omit this: it violates the settled window-selectable-unit definition and is unnecessary for either mode.

### Phantom, closing and transient windows

Phantom means “API-visible but not an intended switch target,” not “thumbnail is blank.” AltTab combines two CGS lists (visible-tagged versus all) with legitimate exemptions: a tab, minimized window, hidden-app window, or known other-Space window is not phantom; absence from all Spaces is a strong signal, and invisible-on-a-visible-Space is a weak signal ([PhantomWindowDetector.swift:31](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/PhantomWindowDetector.swift:31), [PhantomWindowDetector.swift:35](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/PhantomWindowDetector.swift:35)). Phantom windows are always filtered ([WindowFilterResolver.swift:29](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowFilterResolver.swift:29)). Dead phantoms are periodically reconciled against authoritative WindowServer existence ([Applications.swift:37](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:37)).

Order-out is not treated as close. AltTab probes AX liveness: invalid element confirms closure and removes the model; a live element is merely minimized, hidden, or off-Space; transient `cannotComplete` is retried ([Applications.swift:237](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Applications.swift:237)). Destroy events are the backstop. This OS-confirmed, non-optimistic lifecycle policy is essential for Altty.

## Filtering and ordering at summon time

The show path operates on cached model state: recompute the cheap phantom verdict, evaluate filters, then sort ([Windows.swift:79](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:79)). The pure filter composes phantom suppression, Exceptions, active/non-active app, hidden/windowless/fullscreen/minimized, Space, screen and tab rules ([WindowFilterResolver.swift:14](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowFilterResolver.swift:14)). For Altty this kernel can be much smaller: qualification + not phantom + Hide exception + mode owner-PID condition. Unless later product decisions say otherwise, minimized, hidden, fullscreen and other-Space windows should remain eligible because focusing semantics explicitly support them.

AltTab supports multiple sort orders, but recently focused is simply ascending `lastFocusOrder`; optional hidden/minimized/windowless end buckets precede it ([WindowOrderResolver.swift:24](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/WindowOrderResolver.swift:24)). Altty's settled behavior needs MRU only. Stable tie-breaking is still needed during cold-start seeding or simultaneous discovery; creation order/WID can supply determinism.

## Focus transaction

For a real external window, AltTab:

1. records that the coming focus was switcher-initiated, protecting MRU from racy event interpretation;
2. deminimizes through AX when necessary;
3. privately fronts the process and the specific WID (`_SLPSSetFrontProcessWithOptions`), which also switches Space;
4. makes the WID key with a synthetic no-content click;
5. performs `kAXRaiseAction`, reacquiring a stale AX element and retrying if necessary;
6. for cross-Space focus only, repairs the origin Space's remembered front process to avoid future app-window leakage.

The implementation and rationale are documented together at [Window.swift:250](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Window.swift:250) and [Window.swift:274](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Window.swift:274). This is substantially stronger than `NSRunningApplication.activate` + `kAXRaiseAction`, which the source says is not reliable for targeting one cross-app window on modern macOS ([Window.swift:284](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Window.swift:284)). Altty therefore needs an explicit private-API focus adapter and a degraded public-API fallback policy; platform/distribution research must confirm the signing/notarization risk.

## Capture-only code that Altty should exclude

`WindowCaptureEvents.swift`, `WindowCaptureScreenshots`, `WindowThumbnails`, cached `SCWindow` objects, thumbnail throttling/refresh, preview panels and IOSurface cleanup are presentation/capture concerns. They do not discover, qualify, order, track, filter, or focus a window. For example, model removal contains explicit thumbnail/preview resource cleanup, but WID removal, subscriptions, MRU compaction and tab dissolution are separate operations ([Windows.swift:453](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:453), [Windows.swift:472](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Windows.swift:472)). Altty should retain app icons if desired (they do not need Screen Recording), but must not include ScreenCaptureKit, screenshot queues, thumbnail refresh events, capture caches, preview panels or Screen Recording permission.

## Implementation-relevant decisions and follow-up tickets

Decisions supported directly by the evidence:

- Use one cached WID-keyed inventory and one global MRU; apply an invocation-scoped owner-PID predicate for Option-Grave.
- Keep minimized, hidden, fullscreen and other-Space windows as real eligible windows; distinguish them from phantoms and closes.
- Do not add windowless application placeholders.
- Keep capture entirely outside the architecture.
- Treat focus and discovery private APIs as isolated ports with testable policy kernels and degradation behavior.

Newly sharp questions/tickets:

1. **Decide native-tab semantics.** Every-tab support requires inactive-tab AX discovery, group identity/state propagation and tab-switch MRU tests; active-tab-only is much simpler.
2. **Specify cold-start MRU seeding.** Live focus events only establish future order; define deterministic initial ordering for windows found at launch.
3. **Specify degraded focus behavior.** Define what the UI reports when private specific-WID fronting, AX deminimize/raise, Space switching, or AX reacquisition fails.
4. **Create compatibility-fixture policy.** Start with generic level/role/size qualification and add app exceptions only from reproducible cases, with bundle/version/window facts captured as fixtures.
5. **Cross-link platform research.** Validate macOS 15–current behavior, Intel/Apple Silicon availability, and Developer ID/notarization implications for SkyLight enumeration and `_SLPS` focus calls.
