# Private adapter and permission lifecycle validation

## Status

Partial validation completed on 2026-07-13. The Wayfinder task remains open because this machine does not have the final Developer ID identity, notarization credentials, full Xcode, macOS 26, or an explicitly initiated focus test setup. The product now supports arm64 only, so native Intel validation is no longer required.

## Environment

| Dimension | Observed value | Evidence level |
|---|---|---|
| Hardware | Mac mini (M1), arm64 | Native |
| OS | macOS 15.7.7, build 24G720 | Native |
| Swift | 6.2.3, target arm64-apple-macosx15.0 | Native toolchain |
| Xcode | Not installed; Command Line Tools active | Environment audit |
| Developer ID | No valid code-signing identities | `security find-identity -v -p codesigning` |
| Notarization | No `altty-notary` keychain profile | `notarytool history` |
| Accessibility | Trusted in the current responsible-process context | Probe runtime check; not final app identity |
| Spaces/displays | One managed Space on one display during probe | Private read-only query |

The permanent production bundle ID is `app.altty.macos`, now present in `Resources/Info.plist`. It still needs to be registered as an Explicit App ID under the intended Apple Developer Team.

## Probe

The source and one-command runner live in [`private-adapter-probe`](private-adapter-probe/README.md). The probe:

- dynamically opens SkyLight through dyld rather than requiring a filesystem binary;
- resolves every private symbol currently required for discovery, batched window state and focus;
- executes only managed-Space and window-list reads;
- checks Accessibility trust;
- never invokes the focus symbols or changes window state;
- compiles for a macOS 15 deployment target and is ad-hoc signed with hardened runtime.

Run natively:

```sh
sh .scratch/altty-window-switcher/validation/private-adapter-probe/run.sh
```

Run the x86_64 slice through Rosetta:

```sh
ARCHITECTURE=x86_64 sh .scratch/altty-window-switcher/validation/private-adapter-probe/run.sh
```

## Results

### Native arm64 on macOS 15.7.7

- PASS: hardened ad-hoc signature verification.
- PASS: `dlopen` of SkyLight even though its filesystem executable symlink is broken; the framework is supplied through dyld shared cache.
- PASS: all required symbols resolved, including `CGSCopyManagedDisplaySpaces`, `CGSCopyWindowsWithOptionsAndTags`, `SLSWindowQueryWindows`, iterator getters, `_SLPSSetFrontProcessWithOptions`, `SLSSpaceSetFrontPSN`, and `SLPSPostEventRecordTo`.
- PASS: managed-Space query returned one display and one Space.
- PASS: private window enumeration completed without Screen Recording permission or screenshot APIs.
- PASS with qualification: Accessibility reported trusted for this command's current responsible-process context; this says nothing about a final signed Altty app across upgrades.

### x86_64 through Rosetta on the same Apple-silicon host

- PASS: x86_64 compile, hardened ad-hoc signing and execution.
- PASS: the same private symbols and read-only queries succeeded.
- LIMITATION: Rosetta is not native Intel hardware and does not validate Intel WindowServer ABI, performance or TCC identity behavior.

## Not yet validated

- Developer ID Application signing with the final Team ID and bundle ID.
- Notarization, stapling, quarantine-origin launch and Gatekeeper verification.
- Accessibility first grant, denial, retry, revocation and retention across signed upgrades.
- Homebrew versus direct-download identity and permission behavior.
- Specific-WID focus, postcondition verification, fallback and restoration.
- Active-Space focus, fullscreen Active Space, multiple displays and Stage Manager.
- macOS 26 and the next developer beta.

## Exact completion checklist

1. Register the permanent `app.altty.macos` bundle ID under the intended Apple Developer team.
2. Install full Xcode and a valid Developer ID Application certificate on the build machine.
3. Store `notarytool` credentials under a project-specific keychain profile without committing secrets.
4. Package the probe as a minimal LSUIElement app using the final identity, hardened runtime and minimal entitlements.
5. Sign, notarize, staple and download it through a quarantine-preserving route; verify with `codesign`, `spctl` and the notary log.
6. Run the TCC lifecycle matrix: never granted, grant, deny, retry, revoke while running, replace with a signed upgrade, move between install paths, install direct and with Homebrew.
7. Add an explicitly user-triggered focus smoke mode that records origin/target WID and PID, performs the private focus transaction, verifies the focused target, then restores origin.
8. Execute the focus mode on a normal and fullscreen Active Space, with one/multiple displays and Stage Manager on/off.
9. Repeat the read-only and focus matrix on arm64 using the latest shipping macOS 26 release.

## Current architectural signal

The private adapter approach is credible on macOS 15 arm64 and under Rosetta: runtime symbol discovery and read-only Space/window queries work from a hardened process, and failure can be detected without linking private types into the domain. This evidence is sufficient to continue designing an isolated, fail-closed adapter, but not sufficient to claim the final distribution and permission lifecycle validated.
