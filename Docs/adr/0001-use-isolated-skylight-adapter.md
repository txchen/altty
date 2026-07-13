# Use an isolated SkyLight adapter

Altty must reliably focus a specific WID when one application owns multiple windows. Public Accessibility actions do not guarantee that behavior, so Altty accepts the compatibility cost of private APIs: runtime-resolved SkyLight is the sole focus path and the authoritative discovery source for the Active Space, isolated behind `WindowServer`; AX only enriches semantics and performs prerequisites such as deminimizing. If SkyLight is unavailable, Altty leaves switcher shortcuts unregistered rather than providing a lower-guarantee public fallback. Inactive Spaces are intentionally outside the product scope.

## Consequences

- Specific-window switching has one deterministic primary path.
- Private API drift is confined to one replaceable adapter.
- The app must be distributed outside the Mac App Store and tested on every supported macOS and CPU family.
- A future macOS release can temporarily disable switching until compatibility is restored.
- Public-only degraded switching is intentionally unavailable.
- Final Developer ID, notarization, TCC and hardware/OS validation remains a release gate.
