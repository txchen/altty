Status: ready-for-agent

## Problem Statement

macOS provides application switching, but it does not provide a fast, compact and configurable way to switch directly between individual windows across applications. Users who work with several windows from the same application need a window-first MRU workflow: one shortcut for all eligible windows and another for the current application's windows. Existing mature tools demonstrate the desired interaction, but Altty needs an independently implemented, smaller product that omits screenshots, previews, search and secondary window actions.

Altty must behave reliably enough to replace a habitual system interaction. A quick key tap must switch immediately without flashing UI, a longer interaction must present a stable list, and selecting one of several windows owned by the same application must focus the exact window. It must remain a lightweight menu-bar utility, preserve foreground applications' shortcuts through Exceptions, fail closed when permissions or private capabilities are unavailable, and ship as a signed and notarized Apple-silicon application through direct download and Homebrew.

## Solution

Build Altty as a Swift/AppKit menu-bar application for Apple silicon on macOS 15 and later. Option-Tab opens the All-Windows Switcher over Switchable Windows on the Active Space in global MRU order. Option-Grave opens the Current-App Switcher by filtering the same MRU to the application that was frontmost when the Switcher Session began. Both shortcuts are configurable, and Shift reverses navigation.

A quick press and release switches to the next window immediately. If the interaction continues for approximately 100–150 ms, Altty displays a compact centered vertical list with application icons, window titles, application names and relevant state badges. Navigation changes only the temporary selection; it never previews or focuses windows. Releasing the configured modifiers confirms, Escape cancels, and mouse hover, click and wheel share the same selection model.

Altty maintains an event-driven, Active-Space-only inventory keyed by Window ID. SkyLight is the authoritative discovery source and the sole specific-WID focus path. Accessibility enriches records with semantic properties and performs prerequisites such as deminimizing, but it is never a focus fallback. Focus success is verified before MRU promotion. If Accessibility trust or required SkyLight capability is unavailable, Altty unregisters its shortcuts and leaves its menu and Settings available for explanation and recovery.

The production app uses the permanent bundle ID `app.altty.macos`. It ships as an immutable, Developer ID-signed and notarized arm64 ZIP through approval-gated GitHub Releases, with the same artifact consumed by a project-owned Homebrew Cask. The first release performs no background networking or in-app updates; Check for Updates opens the GitHub Releases page.

## User Stories

1. As a macOS user, I want Option-Tab to select individual windows across applications, so that I can switch directly to the work item I need.
2. As a macOS user, I want Option-Grave to select windows belonging only to the currently active application, so that I can move quickly among that application's windows.
3. As a user with several windows in one application, I want every real window to appear as a separate list item, so that application identity does not hide the window I need.
4. As a user of native tabs, I want the containing window to be the selectable item, so that inactive tabs do not appear as fake windows.
5. As a user who taps Option-Tab quickly, I want Altty to switch to the next window even when the list never appears, so that rapid switching feels immediate.
6. As a user who holds the shortcut, I want a list to appear after a short delay, so that I can inspect and choose among several candidates without flashing UI during quick taps.
7. As a user, I want the first forward invocation to select the next MRU window rather than the current window, so that one tap always makes progress.
8. As a user, I want Shift plus the configured shortcut to navigate backward, so that I can reverse direction without a separate binding.
9. As a user, I want navigation to wrap at both ends of the list, so that repeated presses remain predictable.
10. As a user, I want releasing all configured hold modifiers to confirm the current selection, so that the interaction matches established macOS switching habits.
11. As a user, I want Escape to cancel without changing focus or MRU, so that I can safely abandon a selection.
12. As a user, I want an outside click or lost interaction context to cancel safely, so that Altty never leaves a stale session active.
13. As a mouse user, I want hover to move the temporary selection, so that I can inspect the list without keyboard-only navigation.
14. As a mouse user, I want clicking a row to confirm it immediately, so that selection requires one direct action.
15. As a mouse user, I want the scroll wheel to cycle the selection with wraparound, so that long lists remain quick to navigate.
16. As a user, I want navigation to leave the invoking window in front until confirmation, so that browsing candidates does not disrupt my desktop.
17. As a user, I want the candidate list to remain stable during a Switcher Session, so that windows do not jump while I choose.
18. As a user, I want a newly created window to wait until the next session, so that the current list remains understandable.
19. As a user, I want a window that closes during a session to disappear immediately, so that I cannot confirm an invalid target.
20. As a user, I want selection to move safely after a candidate closes, so that the session can continue without an error.
21. As a user, I want minimized windows on the Active Space to remain selectable, so that Altty can restore and focus them.
22. As a user, I want windows of hidden applications on the Active Space to remain selectable, so that hidden applications do not lose their place in my workflow.
23. As a fullscreen user, I want the currently presented fullscreen Space to count as the Active Space, so that Altty works inside fullscreen workflows.
24. As a user who does not use multiple Spaces, I want Altty to ignore windows on inactive Spaces, so that it avoids unnecessary complexity and resource use.
25. As a user, I want list order to reflect real recent focus history, so that likely targets appear first.
26. As a user starting Altty for the first time, I want a deterministic front-to-back seed order, so that the list is useful before Altty has observed focus history.
27. As a user, I want MRU to reset on app restart rather than preserve stale WIDs, so that reused window identifiers cannot corrupt ordering.
28. As a user, I want confirmation to focus the exact selected window, so that an application with multiple windows does not activate the wrong one.
29. As a user, I want Altty to verify the focused WID before reporting success, so that a private API return value alone cannot create false success.
30. As a user, I want MRU to change only after verified focus, so that failures do not degrade future ordering.
31. As a user, I want a failed focus to leave or restore my original window when possible, so that Altty does not strand me in an unintended application.
32. As a user, I want a short nonblocking failure message when switching cannot complete, so that I understand what happened without a modal interruption.
33. As a user, I want a compact vertical list rather than screenshots or thumbnails, so that switching remains fast, private and visually lightweight.
34. As a user, I want each row to show an application icon, window title and application name, so that I can distinguish similarly named windows.
35. As a user, I want minimized, hidden and fullscreen state shown compactly where relevant, so that I can anticipate the result of switching.
36. As a user, I want long text truncated while icons and state remain aligned, so that the list stays scannable.
37. As a user with many windows, I want roughly six to eight rows visible with vertical scrolling and the selection kept in view, so that density remains consistent.
38. As a multi-display user, I want the panel centered on the pointer's display, with sensible invoking-window and primary-display fallbacks, so that it appears where I am working.
39. As a user, I want to configure one shortcut for each switcher mode, so that Altty fits my keyboard habits.
40. As a user, I want Option, Control and Command combinations supported while Shift remains reserved for reverse navigation, so that shortcut semantics stay consistent.
41. As a user, I want conflicting shortcut changes rejected atomically, so that one invalid edit cannot leave half of my bindings broken.
42. As a user, I want Altty to preserve the previous valid shortcut pair after a conflict, so that settings edits cannot disable a working configuration.
43. As a user, I want Altty not to modify native macOS shortcut preferences, so that uninstalling or quitting it leaves system behavior unchanged.
44. As a remote-desktop or game-streaming user, I want an Exception Rule to disable Altty while a chosen application is frontmost, so that the application receives Option-Tab itself.
45. As a user, I want Ignore Always and Ignore When Fullscreen choices, so that shortcut suppression can match how I use an application.
46. As a user, I want ignored shortcuts genuinely unregistered or passed through, so that Altty never consumes a chord and silently does nothing.
47. As a user, I want Hide rules to remove matching applications' windows from both switcher modes, so that unwanted utility windows do not appear.
48. As a user, I want Hide and Ignore to be independent, so that I can hide candidates without disabling shortcuts or do the reverse.
49. As an advanced user, I want exact bundle-ID and explicit prefix matching, so that I can target one application or a controlled application family.
50. As a user with overlapping rules, I want restrictions combined by union and strongest Ignore level, so that behavior does not depend on list order.
51. As a user, I want Exceptions to avoid title matching, so that changing window content cannot unexpectedly alter policy.
52. As a user, I want no Exceptions enabled by default, so that Altty does not silently exclude applications.
53. As a user, I want to add Exceptions from running apps, an application picker or manual bundle-ID entry, so that common and advanced workflows are both supported.
54. As a user, I want missing or uninstalled applications' rules retained, so that reinstalling an app restores the intended behavior.
55. As a user, I want a standard Settings window with General, Shortcuts, Exceptions and About panes, so that configuration follows macOS conventions.
56. As a user, I want permission and malformed-settings warnings shown inline, so that startup is not blocked by modal dialogs.
57. As a user, I want the menu-bar menu to show readiness, permission action, Settings, update check and Quit, so that essential controls remain accessible without a Dock icon.
58. As a new user, I want a clear Accessibility explanation and a user-triggered system prompt, so that I understand why the permission is required.
59. As a user who denies Accessibility, I want Altty to stop prompting repeatedly, so that it respects my decision.
60. As a user who later grants Accessibility, I want switching to become available without restarting Altty, so that recovery is immediate.
61. As a user who revokes Accessibility while Altty runs, I want active sessions ended and shortcuts unregistered, so that Altty cannot consume unusable input.
62. As a user on an incompatible macOS build, I want SkyLight capability failure to disable switching clearly, so that Altty never substitutes an unreliable public focus path.
63. As a privacy-conscious user, I want no screenshots, Screen Recording request, background networking or telemetry upload, so that Altty observes only what switching requires.
64. As a privacy-conscious user, I want diagnostics to exclude window titles and user content, so that troubleshooting does not leak my work.
65. As a user, I want settings to survive normal app and Homebrew upgrades, so that updates do not reset my workflow.
66. As a user with a damaged settings file, I want safe defaults plus a visible warning while the damaged input is preserved, so that Altty recovers without silently destroying evidence.
67. As a user, I want Check for Updates to open the releases page only when I request it, so that Altty remains network-silent in the background.
68. As a Homebrew user, I want to install and upgrade the same notarized artifact as manual-download users, so that distribution paths do not diverge.
69. As a user uninstalling Altty normally, I want my settings retained, so that reinstalling restores my configuration.
70. As a user choosing a Homebrew zap, I want settings, cache and logs removed without tampering with macOS TCC, so that cleanup is explicit and safe.
71. As an Apple-silicon user, I want a native arm64 build with macOS 15 as its minimum, so that the app is optimized for the supported platform.
72. As a maintainer, I want immutable release artifacts and forward patch fixes, so that checksums and historical downloads remain trustworthy.
73. As a maintainer, I want failed signing, notarization or verification to block GitHub Release and Cask updates, so that incomplete builds cannot reach users.
74. As a maintainer, I want release results linked to an exact build SHA, so that every supported artifact has auditable evidence.

## Implementation Decisions

- Rebuild the production source from scratch. The existing prototype source is disposable and imposes no compatibility requirement. Retain project metadata, resources and packaging logic only after reviewing each item against this spec.
- Use one Swift/AppKit executable target rather than multiple Swift packages. Set the minimum deployment target to macOS 15 and produce arm64 only.
- Run as a menu-bar application with no Dock icon.
- Use the permanent production bundle ID `app.altty.macos`. Development, test and nightly builds use distinct identities. Keep the production bundle ID, Team ID and designated requirement stable after formal distribution.
- Organize the executable into Application, Input, WindowServer, Accessibility, Inventory, Switching, Exceptions, Persistence, Presentation and Diagnostics areas with narrow protocol boundaries.
- Keep all AppKit UI, Switcher Session coordination and observable application state on `@MainActor`.
- Use a `WindowInventory` actor to serialize the Active-Space inventory and global MRU.
- Use `SwitcherEngine` as the primary application-service and testing seam. It accepts shortcut/session commands, immutable adapter events, settings snapshots, permission/capability states and a controllable clock. It emits UI/session snapshots and effects for shortcut registration, SkyLight focus, persistence and user-visible status.
- Keep UI and Input dependent on Switching. Switching consumes Inventory and adapter protocols. Concrete WindowServer and Accessibility adapters remain at the edge and never depend on UI.
- Isolate every SkyLight declaration, dynamic symbol, function pointer and private type inside WindowServer. Private types must not enter domain records, settings or presentation.
- At startup, dynamically resolve required SkyLight symbols and perform a read-only capability query. Do not register switcher shortcuts when required capability is unavailable. Provide a user-triggered recheck and do not poll repeatedly.
- Use SkyLight as the authoritative discovery source for the Active Space and as the sole specific-WID focus mechanism. Do not provide AX raise or application activation as a focus fallback.
- Use Accessibility for titles, roles, minimized state and other semantics, and for prerequisite actions such as deminimizing. Bound AX latency off the main thread and model unavailable/stale fields.
- Use `NSWorkspace` for application lifecycle, hidden state and frontmost-application facts.
- Treat SkyLight/WindowServer events as authoritative for WID existence, create/destroy, focus and Active Space changes. A verified Altty focus transaction is authoritative for its MRU promotion.
- Translate all adapter callbacks into immutable events before submitting them to the inventory or SwitcherEngine. Resolve conflicting facts by field ownership; mark uncertain values stale instead of guessing.
- Maintain only windows on the Active Space. A currently presented fullscreen Space is the Active Space. When the Active Space changes, replace the inventory rather than tracking inactive Spaces.
- Key a live record by WID and validate events against PID plus the current inventory generation. Increment generation on an Active-Space rebuild. Delete missing WIDs immediately. A reused WID with a different PID or generation is a new window and inherits no MRU.
- Do not maintain timed tombstones or persist WIDs/MRU across launches.
- Build the initial inventory after Accessibility is available. Update primarily from events. Reconcile on launch, wake, permission recovery, adapter restart or a dirty pre-session state; never poll on a fixed idle cadence.
- Coalesce event bursts over approximately 50–100 ms. Load expensive AX semantics lazily for candidate windows and never block shortcut-to-selection behavior on enrichment.
- Use one global MRU for both switcher modes. Current-App filters it by the invocation-snapshotted frontmost PID.
- On cold start, seed Active-Space candidates from WindowServer front-to-back order, followed by minimized and hidden windows with deterministic creation/WID tie-breaking.
- Model a Switcher Session as an immutable mode, invocation PID, ordered `WindowSnapshot` candidates and temporary selection. New candidates wait until the next session. Destruction may remove candidates; other mutations appear in the next session.
- A quick shortcut press begins selection immediately from cached state. Present the panel only if the session remains active after approximately 100–150 ms.
- If inventory initialization is incomplete, limited AX discovery may form candidates, but confirmation still requires the SkyLight focus path.
- With no candidates, show no panel and perform no action. With only the current window, do nothing. With one different candidate, focus it directly without showing a list.
- Initial forward selection is the item after the current focused window; initial reverse selection is the previous item. If the current window is absent, choose first for forward and last for reverse. Both directions wrap.
- Repeating the active mode's main key cycles forward; Shift cycles backward. Releasing all configured modifiers confirms. Escape, outside click, lost context or abnormal interruption cancels.
- Hover changes the shared temporary selection, click confirms immediately and mouse wheel cycles with wraparound. Navigation never focuses or previews candidates.
- Confirmation performs one focus transaction: deminimize through AX if required, target the specific WID through SkyLight, perform any required AX semantic follow-up, then verify frontmost PID and target window. Only verified success updates MRU.
- On focus failure, do not attempt a public focus fallback. Preserve or restore the invocation window when possible, close the session, show a nonblocking error and leave MRU unchanged.
- Provide exactly one configurable binding for All-Windows and one for Current-App. Defaults are Option-Tab and Option-Grave.
- A binding contains a main key and a nonempty combination of Option, Control and Command. Shift is reserved for reverse navigation. Bare keys, Shift-required base bindings and multiple bindings per mode are unsupported.
- Atomically register a proposed pair before replacing the valid pair. Reject duplicate or externally conflicting bindings, retain both old bindings and show an inline error.
- Do not mutate macOS native shortcut settings.
- Model an Exception Rule by a nonempty exact bundle ID or an explicitly selected bundle-ID prefix. Running-app and application pickers create exact rules by default.
- Keep Hide as an independent Boolean and Ignore as None, Always or When Fullscreen. Matching rules combine by union; strongest Ignore wins. Exact rules do not negate prefixes and list order has no policy meaning.
- Hide excludes every matching real window from both modes. Ignore disables both switcher shortcuts while a matching application is frontmost; When Fullscreen additionally requires its current window to be fullscreen.
- Recompute Ignore when frontmost application or fullscreen state changes. Ensure ignored shortcuts pass through rather than being consumed as a no-op.
- Do not support title matching, negative/allow rules or windowless-application conditions. Ship an empty Exception list.
- Support Exception creation from running apps, an application-bundle picker and advanced manual ID entry. Duplicate identities edit the existing rule. Preserve rules for missing apps.
- Persist a single versioned `SettingsSnapshot` as JSON under Application Support. Include shortcuts, Exceptions, launch behavior and UI preferences in one validated transaction.
- Save using temporary-file plus atomic replacement. Apply explicit sequential schema migrations. On corrupt or unsupported input, preserve the file for diagnosis, load safe defaults and show an inline warning.
- Do not persist inventory, MRU, WIDs, AX elements or adapter health. Do not use Keychain for runtime settings. Do not provide iCloud sync, import or export in the first release.
- Apply shortcut changes after an active session ends. Apply Exception changes to the next session. Failed setting replacement preserves the complete prior valid snapshot.
- Use a compact centered translucent vertical AppKit panel, visually independent from AltTab's grid. Show mode and shortcut in the header.
- Show application icon, window title, application name and relevant minimized/hidden/fullscreen badges per row. Truncate text to one line while preserving icon and badge alignment.
- Use a full-row accent selection. Show about six to eight rows before scrolling and keep the selected row visible.
- Center the panel on the pointer's display, falling back to invoking-window display and then primary display. Never span displays.
- Provide a conventional Settings sidebar with General, Shortcuts, Exceptions and About. Keep permission and malformed-settings warnings inline.
- Provide readiness/permission status, Settings, Accessibility action, Check for Updates and Quit in the menu-bar menu.
- General contains Accessibility status/action, launch-at-login and basic list presentation. Shortcuts contains two recorder controls and inline conflicts. Exceptions contains management-first Add/Edit/Delete rows. About contains version and project/support/update links.
- Do not include search, thumbnails, screenshots, ScreenCaptureKit, preview panels, live focus, arrow navigation, number selection or secondary window actions.
- Keep Diagnostics local and structured. Record error categories, capability, permission and performance facts but never window titles or other user content. Upload no telemetry.
- Target under 0.2% average idle CPU over five minutes and under 50 MB idle resident memory. Permit no fixed idle polling or unexplained AX/SkyLight work.
- Target warm-cache shortcut-to-focus-start p95 below 30 ms, panel presentation at 100–150 ms and 100-window filter/sort/snapshot p95 below 10 ms.
- Use one narrow `UpdateAction` boundary. The first implementation opens the latest GitHub Releases page. Perform no startup checks, API calls, background requests, downloads or in-app installs. Do not ship Sparkle.
- Publish immutable `Altty-<version>-arm64.zip` artifacts and SHA-256 checksums through GitHub Releases. Do not publish DMG, x86_64 or universal artifacts in the first release.
- Use semantic `MAJOR.MINOR.PATCH` tags and short versions, with a CI-generated monotonically increasing integer build version. Never replace an existing artifact.
- Start distribution through a project-owned Homebrew tap. The Cask installs into `/Applications`, requires arm64/macOS 15+, and consumes the exact GitHub artifact. Normal uninstall retains settings; explicit zap removes settings/cache/logs without modifying TCC.
- Produce formal releases only from an approval-protected tag-triggered GitHub Actions workflow. Use an ephemeral keychain, Developer ID Application certificate and App Store Connect API key; enable hardened runtime and secure timestamp; notarize, staple, rebuild the ZIP and verify before publication.
- Reject sandbox, `get-task-allow`, disable-library-validation and unapproved runtime-exception entitlements.
- Use immutable releases and forward patch fixes. Signed/notarized `-rc.N` prereleases may validate the production TCC identity under controlled distribution but never update the stable Homebrew tap.

## Testing Decisions

- Test externally visible state transitions and effects through `SwitcherEngine`, not actor implementation, collection layout, AppKit controller internals or private adapter helpers.
- The primary deterministic seam accepts commands, adapter events, settings, permission/capability states and a fake clock, then exposes immutable UI/session state and requested effects. This is the default seam for policy, orchestration, failure and race tests.
- Use a second explicit macOS system seam only for behavior that cannot be proven in-process: SkyLight symbol/query/focus, Accessibility/TCC, Carbon/event-tap delivery, real AppKit keyboard/panel interaction, sleep/wake, signing, notarization, Gatekeeper and Homebrew.
- Pure tests cover candidate qualification, Active-Space filtering, Current-App PID filtering, MRU seed/promotion, initial selection, forward/reverse wrap, stable session snapshots, Exceptions union/strength, shortcut validation and settings migrations.
- Deterministic adapter tests inject fake WindowServer, AX, Workspace and clock implementations. Cover target/candidate closure, WID reuse, missing/stale/timed-out AX data, app exit/hang, SkyLight unavailable/query/focus failure, false-success postconditions, event reordering, permission revocation at every phase, shortcut failure, generation rebuild during a session, corrupt/future/interrupted settings, duplicated/lost/burst events, wake reconstruction and rapid cross-mode input.
- Every failure test asserts no crash, no unhandled shortcut capture, no false focus success, no incorrect MRU promotion, safe session termination and no window-title/user-content logging.
- Keep replayable event-trace fixtures title-free so races found on real systems can become deterministic regressions.
- Test UI behavior at the highest AppKit seam that observes panel content, selection and actions. Do not snapshot private view hierarchy structure. Verify display choice, delayed visibility, row overflow, truncation, scrolling, mouse interactions and inline warnings.
- Run real keyboard and focus tests only through an explicitly initiated smoke runner so normal CI never changes the user's focus.
- Real system tests cover Option-Tab/Option-Grave, Shift reverse, modifier release, shortcut conflicts, event-tap creation/failure, exact WID focus, minimized restoration, same-app multiple windows, fullscreen Active Space, multiple displays and Stage Manager.
- Accessibility lifecycle tests cover clean trust, grant, denial, explicit retry, runtime revocation, regrant without restart, observer/inventory rebuild, signed upgrade, direct ZIP, Homebrew install/upgrade/cross-replacement, app movement, separate dev/release identities, changed designated requirement, sleep/wake and OS update.
- Compatibility is declared only after testing the latest patch of minimum macOS 15 and each advertised major. Run the full capability/focus matrix before adding a new major. Never infer support from a version number alone.
- Cover at least an M1 baseline and a newer Apple-silicon device; Finder, Safari, Terminal, System Settings, an Electron application and a nonstandard-window application; ANSI and non-ANSI layouts.
- Run a read-only SkyLight smoke after macOS security updates. Run explicit focus smoke before declaring that update supported.
- Over a five-minute authorized Release-build idle run, assert average CPU below 0.2%, resident memory below 50 MB, zero polling and no uncaused AX/SkyLight calls.
- Measure warm-cache shortcut-to-focus-start p50/p95/p99 with p95 below 30 ms. Measure panel timing within 100–150 ms and 100-window snapshot p95 below 10 ms.
- After 1,000 create/destroy events and 100 rapid switches, assert inventory records, observers, AX references, shortcut registration, memory and MRU return to a correct stable baseline.
- Feed 100 events/second for ten seconds and assert coalescing prevents linear AX amplification and main-thread stalls.
- CI enforces deterministic functional, race and microbenchmark regression. Clean RC hardware records real CPU, memory, wakeups, adapter call counts and end-to-end latency with hardware, OS and build SHA.
- A release candidate must be arm64 with macOS 15 deployment target, correctly nested-signed with the production team, hardened and timestamped, and free of unapproved entitlements.
- Release verification requires strict codesign validation, Gatekeeper acceptance, accepted notarization, staple, final-ZIP revalidation, quarantine-origin launch and matching GitHub/Cask/checksum metadata.
- Test direct install and replacement plus Homebrew clean install, upgrade, uninstall and zap. Verify stable bundle ID, Team ID, designated requirement, version/About/release-notes consistency and absence of test assets, debug symbols, secrets or CI residue.
- Attach every formal result to the exact build SHA. Any failed release gate prevents GitHub Release creation and Homebrew tap update.
- The existing private-adapter probe is prior art for runtime symbol resolution and read-only managed-Space/window queries. The throwaway UI prototype is prior art for presentation behavior only; production views and tests are new.

## Out of Scope

- Mac App Store submission, App Sandbox compromises and App Store distribution.
- Intel Macs, x86_64 builds and universal artifacts.
- Windows on inactive Spaces, cross-Space discovery and cross-Space switching.
- Screenshots, thumbnails, live previews, Screen Recording permission and ScreenCaptureKit.
- Native tabs as separate selectable candidates.
- Windowless application placeholders.
- Search, arrow-key navigation, number selection and cross-mode transition inside one session.
- Window actions such as close, minimize, fullscreen, hide application and quit application.
- Live focus or preview while navigating.
- Title-based Exceptions, negative allow rules and windowless conditions.
- Multiple shortcuts per mode, bare-key shortcuts or Shift as a required base modifier.
- Automatic enabling of suggested Exceptions.
- iCloud/cross-device settings sync, settings import or export.
- Background update checks, GitHub API polling, in-app downloads, automatic installation and Sparkle in the first release.
- DMG packaging in the first release.
- Official `homebrew/cask` acceptance as a launch dependency.
- Telemetry upload or diagnostics containing window titles/user content.
- Copying AltTab source, assets, branding or GPL-covered implementation material.
- Preserving source or behavior compatibility with the existing disposable prototype.
- Supporting an unverified new macOS major or providing public-only degraded focusing when SkyLight is unavailable.

## Further Notes

- Altty is inspired by AltTab's mature behavior but must be implemented independently. The local AltTab checkout and research notes are evidence for macOS behavior and architectural lessons, not a source to copy.
- The accepted architecture deliberately chooses SkyLight as the sole focus path. This is a fail-closed product trade-off: exact-window reliability is preferred over a broader but lower-guarantee public fallback.
- The product intentionally supports only the Active Space because the user does not rely on multiple Spaces. Fullscreen remains supported when its Space is currently active.
- The permanent production bundle ID is `app.altty.macos`. It still must be registered as an Explicit App ID under the eventual organization Apple Developer Team.
- Developer Program enrollment, Developer ID issuance, notarization credentials and final signed TCC/Homebrew lifecycle validation remain external release gates. They do not block deterministic implementation.
- The partial validation probe has passed hardened ad-hoc arm64 runtime symbol resolution and read-only queries on macOS 15.7.7/M1. It has not yet validated production signing, notarization, macOS 26, explicit focus behavior or the final TCC identity.
- The existing package currently targets an older macOS version and contains disposable prototype sources. Implementation must align the target and source tree with this spec before treating existing builds as product evidence.
