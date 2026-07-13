Status: claimed
Type: task
Parent: ../map.md
Blocked by: 02

## Question

Using the intended stable bundle ID, Team ID and Developer ID distribution identity, can a minimal hardened and notarized universal test app on macOS 15+ resolve and exercise the required read-only SkyLight discovery symbols, focus a specific WID on the Active Space with verified postconditions, and retain a predictable Accessibility permission lifecycle across direct-download and Homebrew installs; what exact OS, architecture, TCC, fullscreen and display configurations pass or fail?

## Comments

### 2026-07-13 — Partial validation

[Private adapter and permission lifecycle validation](../validation/private-adapter-validation.md) records the completed macOS 15.7.7/M1 work and the exact remaining matrix.

Read-only SkyLight symbol resolution and Space/window queries pass from hardened ad-hoc arm64 and Rosetta x86_64 probes. The task remains claimed rather than resolved: this machine has no Developer ID Application identity, notarization profile or full Xcode, and current coverage lacks native Intel, macOS 26 and an explicitly user-observed Active-Space focus test.
