Status: claimed
Type: task
Parent: ../map.md
Blocked by: 02

## Question

Using the intended stable bundle ID, Team ID and Developer ID distribution identity, can a minimal hardened and notarized arm64 test app on macOS 15+ resolve and exercise the required read-only SkyLight discovery symbols, focus a specific WID on the Active Space with verified postconditions, and retain a predictable Accessibility permission lifecycle across direct-download and Homebrew installs; what exact OS, TCC, fullscreen and display configurations pass or fail?

## Comments

### 2026-07-13 — Partial validation

[Private adapter and permission lifecycle validation](../validation/private-adapter-validation.md) records the completed macOS 15.7.7/M1 work and the exact remaining matrix.

Read-only SkyLight symbol resolution and Space/window queries pass from a hardened ad-hoc arm64 probe; the earlier Rosetta x86_64 result is historical extra coverage and no longer part of the release requirement. The task remains claimed rather than resolved: this machine has no Developer ID Application identity, notarization profile or full Xcode, and current coverage lacks macOS 26 and an explicitly user-observed Active-Space focus test.
