Status: resolved
Type: research
Parent: ../map.md
Blocked by:

## Question

How does the current local AltTab implementation discover, qualify, order, track, and focus windows—including minimized and hidden windows, tabs, fullscreen windows, other Spaces, windowless applications, and phantom or transient windows—and which parts are essential for Altty's two switcher modes without any capture features?

## Answer

Resolved in [AltTab window model research](../research/alttab-window-model.md).

AltTab maintains a long-lived, WID-keyed inventory: SkyLight/WindowServer supplies cross-Space discovery, lifecycle, geometry, Space/fullscreen state and focus events, while Accessibility supplies semantic qualification, minimized/title/tab facts and window actions. Altty should use one cached inventory and global MRU, filter the invocation-snapshotted owner PID for Current-App mode, keep minimized/hidden/fullscreen/other-Space windows eligible, omit windowless placeholders and all capture code, and isolate private discovery/focus adapters with explicit degradation policies.
