# 18 — Finish Settings, menu and presentation polish

**What to build:** Complete the production-facing Altty experience around the working switchers: polished compact list placement, full Settings content, menu-bar status, launch behavior and manual update/support information.

**Blocked by:** 17 — Apply persistent Exception Rules

**Status:** ready-for-agent

- [ ] The compact list uses native translucent styling, full-row accent selection and legible primary/secondary/state text without copying AltTab branding or layout.
- [ ] Long titles/application names truncate to one line; icons and badges remain aligned; roughly six to eight rows show before vertical overflow and selection stays visible.
- [ ] Invocation centers the panel on the pointer's display, falling back to the invoking window's display and then the primary display, and never spans displays.
- [ ] General Settings includes Accessibility/readiness action, launch at login and supported list-presentation basics.
- [ ] Shortcuts and Exceptions panes present every behavior from their completed slices with inline validation/recovery.
- [ ] About presents product/version information, project/support links and Check for Updates.
- [ ] Check for Updates opens the latest GitHub Releases page in the default browser and performs no background version or network request.
- [ ] The menu-bar menu shows readiness/permission status, Settings, Accessibility action, Check for Updates and Quit without candidate or Exception management duplication.
- [ ] Permission, compatibility and corrupt-settings warnings appear inline rather than as modal launch blockers.
- [ ] The versioned JSON `SettingsSnapshot` is saved atomically under Application Support with sequential migration and corrupt-file preservation; runtime inventory/MRU state is never persisted.
- [ ] UI accessibility, keyboard focus, multi-display placement, overflow, launch-at-login and browser actions have behavior-level tests.
