# Platform and distribution constraints (macOS 15+)

## Executive decision

Altty can be shipped as a **non-sandboxed, hardened-runtime, Developer ID-signed and notarized menu-bar application** through a direct ZIP or DMG download and Homebrew Cask. Its public-API baseline is viable: Carbon hot-key registration does not itself require Accessibility, and a user-granted Accessibility trust decision enables cross-process AX inspection and actions. However, the product requirement to enumerate windows reliably across Spaces and focus one specific window cannot be guaranteed by Apple's public API contract. The AltTab implementation achieves those behaviors with undocumented SkyLight/CGS symbols, so Altty must treat that layer as a version-sensitive compatibility adapter, not as a supported platform capability.

This is a feasibility conclusion, not a release validation. A signed/notarized Altty build has not yet been exercised on the macOS/CPU matrix described below.

## Evidence classes

- **Apple-confirmed** means the behavior or distribution rule appears in current Apple documentation.
- **Implementation evidence** means the checked-out AltTab source demonstrates a working design, but Apple does not promise that the underlying behavior will remain available.
- **Inference / validation needed** means the conclusion follows from those sources but still needs a signed build and real OS testing.

## Capability matrix

| Requirement | Public baseline | Permission | Private dependency / risk | Verdict |
|---|---|---|---|---|
| Register global shortcuts | Carbon `RegisterEventHotKey` (used by AltTab) | None demonstrated for registration itself | Command-Tab ownership and key-down/up interception can require event taps or private symbolic-hot-key control | Viable for ordinary configurable chords; validate conflicts and the exact modifier-release interaction |
| Inspect other apps' windows | Accessibility `AXUIElementCreateApplication`, attribute reads, observers | User must grant Accessibility trust | AX is IPC and can time out, reject actions, or expose incomplete app-specific trees | Supported public route, but failure must be first-class |
| Discover all windows across Spaces | `CGWindowListCopyWindowInfo` exposes window dictionaries in the current user session, but Apple does not document Space identity or promise the desired cross-Space inventory semantics | No separate documented permission for metadata-only use | AltTab uses undocumented CGS managed-Space and window-list calls | Private compatibility seam required for the full requirement |
| Focus a particular cross-app window | Public AX can request supported actions and `NSRunningApplication.activate` can activate an app | Accessibility for AX operations | AltTab uses private `_SLPSSetFrontProcessWithOptions`, `SLSSpaceSetFrontPSN`, and a synthetic WindowServer event to make a WID key | No public guarantee; highest-risk runtime path |
| Ship outside App Store | Developer ID + hardened runtime + notarization | User passes Gatekeeper on launch | Private symbols are not promised by Apple; notarization acceptance is not an API compatibility guarantee | Direct distribution is the correct channel; do not claim private APIs are approved/supported |

## Global hotkeys and keyboard observation

AltTab registers shortcuts through Carbon `RegisterEventHotKey` and checks the returned `OSStatus` ([KeyboardEvents.swift:126](/Users/hibiki/code/github/alt-tab-macos/src/events/KeyboardEvents.swift:126)). That is strong implementation evidence that normal system-wide chord registration can remain independent of AX window access. Registration can fail (for example, a collision), so Altty must surface an unavailable-shortcut state rather than assume ownership.

The interaction contract may need more than registration. AltTab separately installs local monitoring and a `CGEvent` tap ([KeyboardEvents.swift:144](/Users/hibiki/code/github/alt-tab-macos/src/events/KeyboardEvents.swift:144)); its source explicitly notes that event-tap creation can return `nil` without Accessibility ([KeyboardEvents.swift:154](/Users/hibiki/code/github/alt-tab-macos/src/events/KeyboardEvents.swift:154)). Therefore:

1. Use `RegisterEventHotKey` for invocation where possible.
2. Treat any event tap used to observe/consume cycling, modifier release, or conflicting system shortcuts as Accessibility-gated.
3. Avoid changing macOS's native Command-Tab setting. AltTab can do so only through undocumented `CGSSetSymbolicHotKeyEnabled`, whose effect persists after quit ([SkyLight.framework.swift:156](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/SkyLight.framework.swift:156)). Altty should not mutate that global preference in the initial design.

Whether the exact proposed `Option-Tab` / `Option-~` key-up lifecycle works solely with Carbon callbacks on macOS 15 and later is **empirical validation needed**.

## Accessibility permission and cross-application AX

Apple documents `AXIsProcessTrustedWithOptions` as the test for whether the current process is a trusted Accessibility client. `kAXTrustedCheckOptionPrompt` may asynchronously ask the user to grant trust, but prompting does not change the function's immediate return value ([Apple: AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)). Altty therefore needs an explicit onboarding state: explain why access is required, invoke the prompt once in response to the user, and re-check after the user returns from System Settings. It must remain usable enough to explain/retry when trust is absent or revoked.

Once trusted, the public AX API supports creating an application element by PID, reading its attributes, testing settable attributes, setting values, and requesting supported actions. Apple also documents normal failure modes including unsupported action, invalid element, and `kAXErrorCannotComplete` when messaging fails or the target app does not respond ([Apple: AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction)). AltTab consequently imposes a one-second AX messaging timeout and explicitly treats `cannotComplete` as transient ([AXUIElement.swift:9](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/AXUIElement.swift:9)), and bulk-reads title, role, minimized/fullscreen state, focused/main window, position and size ([AXUIElement.swift:103](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/AXUIElement.swift:103)). Altty should copy the architectural rule, not necessarily the exact timeout: isolate calls off the main thread, bound latency, and model unavailable/stale attributes.

No special code-signing entitlement is documented by Apple as the grant for being an Accessibility client; the grant is the user's TCC trust decision. This is distinct from App Sandbox entitlements. The recommended direct-download build is non-sandboxed because the App Sandbox is optional for notarized Developer ID apps ([Apple: Preparing your app for distribution](https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution)). **Validation needed:** confirm TCC identity and upgrade behavior using Altty's final stable bundle ID, Team ID, designated requirement, and install location; development/ad-hoc builds are not adequate proxies for the release permission UX.

## Window discovery and Spaces

Apple's public `CGWindowListCopyWindowInfo` returns dictionaries for selected windows in the **current user session**, including bounds and window ID ([Apple: CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29)). The option constants explicitly exclude other active user sessions ([Apple: Window List Option Constants](https://developer.apple.com/documentation/coregraphics/window-list-option-constants)). `optionOnScreenOnly` means exactly windows currently on screen ([Apple: optionOnScreenOnly](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly)). These documents do not expose Space identifiers or guarantee a complete, actionable all-Space model.

AltTab fills that gap by linking against the private SkyLight framework ([SkyLight.framework.swift:1](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/SkyLight.framework.swift:1)). It obtains managed Spaces with `CGSCopyManagedDisplaySpaces`, with a documented-in-source behavioral dependency on “Displays have separate Spaces” ([SkyLight.framework.swift:39](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/SkyLight.framework.swift:39)), and retrieves WIDs for supplied Spaces using `CGSCopyWindowsWithOptionsAndTags` ([SkyLight.framework.swift:118](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/SkyLight.framework.swift:118)). AltTab's AX wrapper also records that public `kAXWindows` sees only the current Space and uses a WID-oriented workaround for a specific other-Space window ([AXUIElement.swift:173](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/AXUIElement.swift:173)).

Thus the all-Space inventory requirement is **not public-API complete**. Altty should define a narrow `WindowServerAdapter` whose output is WIDs plus Space/display placement, put every private declaration behind it, dynamically check symbol availability where practical, and allow degraded current-Space operation if the adapter fails. Do not let private types escape into the domain model.

## Focusing one particular window

Public AX actions are requests against an accessibility object and can be unsupported or fail. Public `NSRunningApplication.activate` activates an application, not a documented WID-specific cross-Space focus transaction. AltTab's current focus sequence demonstrates the missing seam: it calls `_SLPSSetFrontProcessWithOptions` with the target WID, synthesizes a mouse down/up to make that WID key, and uses `SLSSpaceSetFrontPSN` to avoid corrupting another Space's remembered front app ([Window.swift:287](/Users/hibiki/code/github/alt-tab-macos/src/switcher/state/Window.swift:287); [SkyLight.framework.swift:180](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/SkyLight.framework.swift:180); [SkyLight.framework.swift:230](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/SkyLight.framework.swift:230)). The source describes the event-record layout as reverse-engineered and includes an OS-specific buffer change after macOS 14.7.4 ([SkyLight.framework.swift:199](/Users/hibiki/code/github/alt-tab-macos/src/macos/api-wrappers/SkyLight.framework.swift:199)).

That is direct evidence of OS drift. Altty must regard specific-window focus as an atomic best-effort operation with postcondition verification (front PID, focused WID/AX element where obtainable), retry only when safe, and a fallback to public app activation. It must never assume a zero `CGError` proves the correct Space/window became focused.

## Hardened runtime, entitlements, signing, and notarization

Apple's current notarization requirements are explicit: sign all distributed executables with the appropriate Developer ID identity, enable hardened runtime, use a secure timestamp, omit `com.apple.security.get-task-allow=true`, link against macOS 10.9 or later, and use correctly formatted entitlements. The service scans for malware and signing issues; it is not App Review. The supported command-line workflow uses `notarytool`, and tickets can be stapled ([Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)). Apple recommends validating policy with `spctl`; hardened runtime can be enabled manually with `codesign --options=runtime` ([Apple: Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)).

The hardened runtime blocks uncommon behaviors such as JIT and library injection by default; exception entitlements should be added only when needed ([Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)). Calling linked system private symbols is not, by itself, documented as requiring a hardened-runtime exception entitlement. Accordingly, start Altty with **no runtime exception entitlements**, no App Sandbox entitlement, and add nothing until a signed release-candidate test demonstrates a need.

AltTab is useful evidence but not a template to copy blindly: it disables App Sandbox and enables `com.apple.security.cs.disable-library-validation` ([alt_tab_macos.entitlements:5](/Users/hibiki/code/github/alt-tab-macos/alt_tab_macos.entitlements:5)), likely because it embeds/update-loads third-party components. Altty's thin, no-screenshot MVP should not inherit that weakened setting without a concrete dependency. AltTab's release script ZIPs the app, submits with `notarytool`, waits for acceptance, staples the app, then recreates the ZIP ([package_and_notarize_release.sh:10](/Users/hibiki/code/github/alt-tab-macos/scripts/package_and_notarize_release.sh:10)); that is a sound shape for Altty's automated release pipeline.

Private API use creates two distinct risks:

- **Compatibility:** undocumented symbols/signatures/semantics may change on any macOS update.
- **Distribution policy:** Developer ID notarization is an automated security/signing check, not an Apple promise that private calls are supported. A successful notarization test is necessary but must not be described as approval.

## Architectures and minimum OS

Ship one universal app containing both `arm64` and `x86_64` slices. Apple states that a universal binary runs natively on Apple silicon and Intel, recommends making every embedded executable/framework universal, and recommends verifying slices with `lipo -archs` ([Apple: Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)). Since Altty targets macOS 15+, set the deployment target to 15.0 and verify every dependency has both slices. Do not rely on Rosetta as Intel support.

Architecture parity matters especially for private calls: compile-time declarations may succeed on both architectures while ABI or runtime behavior differs. The release gate must execute discovery and focus tests natively on at least one Apple-silicon Mac and one Intel Mac running macOS 15.x. A universal binary inspection alone is insufficient.

## ZIP, DMG, and Homebrew Cask

Apple's notary service accepts ZIP archives and UDIF disk images, and can staple a ticket to the app/disk image. A ZIP is the smallest primary artifact for the MVP; a DMG is optional polish rather than a platform requirement. In either case, sign nested code correctly, sign the app with Developer ID Application, notarize the final payload, staple where supported, then run `codesign --verify`, `spctl`, and a quarantine-origin install test.

Homebrew Cask accepts common archives such as `.dmg` and `.zip`; a versioned cask normally requires a version, SHA-256, URL, metadata, and an `app` artifact. It supports a minimum macOS dependency and architecture-specific URLs/checksums, but a single universal artifact avoids those branches ([Homebrew: Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)). Proposed shape:

```ruby
cask "altty" do
  version "…"
  sha256 "…"
  url "https://…/Altty-#{version}.zip"
  name "Altty"
  desc "Window switcher for macOS"
  homepage "https://…"

  depends_on macos: ">= :sequoia"
  app "Altty.app"
end
```

The exact accepted macOS-version stanza syntax and token availability must be checked with `brew audit --cask --new` against the Homebrew version used when submitting. Publish immutable, versioned URLs and checksums. Homebrew installation does not bypass Gatekeeper or grant Accessibility; first-run onboarding remains identical.

## Required release and OS validation matrix

Before calling the private-backed behavior supported, test a **Developer ID-signed, hardened, notarized, quarantined download** rather than an IDE launch.

| Dimension | Minimum coverage |
|---|---|
| Hardware | Apple silicon native; Intel native |
| OS | Latest macOS 15 patch; latest shipping macOS; current developer beta before each major release |
| Install | Direct ZIP; Homebrew Cask; DMG if shipped; clean install and in-place upgrade |
| TCC | Never granted; grant; deny; revoke while running; app upgrade without re-prompt; moved app |
| Spaces | One/multiple Spaces; full-screen Space; multiple displays; “Displays have separate Spaces” on/off; Stage Manager on/off |
| Windows | Normal, minimized, hidden app, full-screen, other Space, multiple windows from one app, unresponsive app, window closing during switch |
| Keyboard | Both defaults, conflict with existing registration, key repeat, modifier release, secure-input contexts, keyboard layouts |
| Distribution checks | `lipo -archs`; recursive signature verification; entitlements dump; `spctl`; notary log; offline launch with stapled ticket |

Private-symbol smoke tests should run automatically at launch without changing focus: resolve required symbols, perform a read-only Space/window query, and record adapter availability. Behavioral focusing tests belong in release QA because they necessarily change user state.

## Sharp decisions for Altty

1. **Distribution:** Developer ID direct download plus Homebrew Cask; no Mac App Store target.
2. **Sandbox:** non-sandboxed. Hardened runtime remains enabled.
3. **Entitlements:** begin with an empty/minimal entitlement set; specifically do not copy AltTab's disable-library-validation exception without demonstrated need.
4. **Permission:** Accessibility is a hard feature gate for cross-app AX and event-tap-dependent interaction, with explicit onboarding and revocation handling. Screen Recording is out of scope because Altty has no screenshots.
5. **Private seam:** isolate SkyLight discovery/focus behind one adapter with symbol checks, postcondition verification, telemetry/logging that contains no window titles, and a public degraded mode.
6. **Artifact:** one universal `arm64` + `x86_64` app in a versioned notarized ZIP; add DMG only for presentation.
7. **Support promise:** macOS 15+ is a tested range, not evidence of future compatibility; each major/beta OS needs a compatibility pass before being declared supported.

## Newly sharp follow-up tickets

- **Prototype signed private adapter on macOS 15+:** build the smallest hardened Developer ID test app that dynamically resolves the exact discovery/focus symbols, notarize it, and record results by OS/architecture/Space configuration.
- **Define degraded-mode contract:** decide what UI and behavior remain when Accessibility is absent or the SkyLight adapter fails (recommended: settings/onboarding plus current-app/public activation fallback; no misleading all-window list).
- **Create release pipeline and verification script:** universal build, nested signing, entitlement assertion, ZIP, `notarytool`, staple, recreate ZIP, `codesign`, `spctl`, `lipo`, checksum.
- **Prototype permission lifecycle:** verify first prompt, denial/retry, revocation, stable identity across upgrades, and Homebrew-vs-direct installation using the final Team ID and bundle ID.
- **Establish OS compatibility CI/QA:** read-only private-symbol smoke test plus a manual focus matrix on macOS 15 patches and every new major beta.
