# Use an isolated SkyLight adapter

Altty must reliably focus a specific WID when one application owns multiple windows. Public Accessibility actions do not guarantee that behavior, so Altty accepts the compatibility cost of private APIs: runtime-resolved SkyLight is the sole focus path and the authoritative discovery source for the Active Space, isolated behind `WindowServer`; AX enriches semantics, deminimizes, and raises the exact target within its owning application after the mandatory SkyLight focus request. If SkyLight is unavailable, Altty leaves switcher shortcuts unregistered rather than providing a lower-guarantee public fallback. Inactive Spaces are intentionally outside the product scope.

## Consequences

- Specific-window switching has one deterministic primary path.
- Private API drift is confined to one replaceable adapter.
- The app must be distributed outside the Mac App Store and tested on every supported macOS and CPU family.
- A future macOS release can temporarily disable switching until compatibility is restored.
- Public-only degraded switching is intentionally unavailable.
- Final Developer ID, notarization, TCC and hardware/OS validation remains a release gate.

## 2026-09-23 — exact-target AX ordering

A real two-window AppKit fixture showed SkyLight returning success while key focus
stayed on its first window, including after a 500 ms observation period. Raising the
same WID through AX after SkyLight made all four alternating requests verify. AXRaise
is therefore a best-effort ordering stage of the single focus path, never a fallback
when SkyLight fails. PID/WID postcondition verification remains mandatory. Focus
mouse-down is sent far outside content/resize handles, with no mouse-up to complete
a click. This corrects the earlier assumption that SkyLight alone was sufficient.
