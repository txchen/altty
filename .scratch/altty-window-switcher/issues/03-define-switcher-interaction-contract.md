Status: resolved
Type: grilling
Parent: ../map.md
Blocked by: 01

## Question

What exact user-visible interaction contract should the All-Windows Switcher and Current-App Switcher implement, including native-tab eligibility, invocation, cold-start MRU seeding, initial selection, forward and reverse cycling, MRU updates, modifier release, cancellation, mouse selection, empty states, focus restoration, and degraded focus failures, after comparing the desired subset with AltTab's behavior?

## Answer

### Candidate model

- A macOS window is the smallest selectable unit. Native tabs are not independent candidates; focusing a tabbed window preserves its currently active tab.
- Both modes use one global MRU. All-Windows admits every eligible window; Current-App snapshots the invoking application's PID when the shortcut begins and filters the same MRU to that owner for the whole session.
- Each Switcher Session snapshots its ordered candidates. Newly created windows wait until the next session; invalid or closed windows are removed immediately, moving selection to the next candidate when necessary. State indicators may update, but remaining candidates do not reorder mid-session.
- Minimized and hidden-app windows on the active Space remain eligible unless filtered by an Exception Rule. A fullscreen Space counts as the active Space when selected. Other-Space windows and windowless applications are never candidates.

### Cold start and ordering

- Before live focus history exists, seed active-Space windows from WindowServer front-to-back order, followed by minimized and hidden windows on that Space with stable creation-order tie-breaking.
- Real focus events progressively replace the seed order. Do not persist window MRU across process restarts.
- List order is MRU. If the current window is present, a forward invocation selects its next item and a reverse invocation selects its previous item. If it is absent, forward selects the first item and reverse selects the last. Cycling wraps at both ends.

### Invocation and display

- Window selection begins immediately from the cached model and never waits for list rendering.
- A quick press-and-release confirms the selected next window even if the panel never appears.
- Delay list presentation by approximately 100–150ms to avoid flashing during a quick switch. The operation itself has no artificial delay.
- While the long-lived model is still initializing, a limited AX discovery fallback may form candidates, but confirmation still uses the required SkyLight focus path; do not cancel solely because the UI or full inventory is not ready.
- No candidates means no panel and no action. A sole candidate equal to the current window means no action. A sole different candidate is focused directly without a panel.

### Navigation, confirmation and cancellation

- Repeating the active mode's main key cycles forward; holding Shift while pressing it cycles backward. Escape cancels. Releasing the configured hold modifier confirms.
- First release supports no arrow-key navigation, cross-mode shortcut transition, number selection or search input.
- Hover changes the shared temporary selection, click confirms immediately, and the mouse wheel cycles the temporary selection with wraparound.
- Moving selection never focuses or previews candidate windows. The invoking window remains in front until confirmation.
- Escape, outside click, lost interaction context or an abnormal shortcut interruption cancels, closes the panel and leaves the invoking window and MRU unchanged.

### Focus and MRU outcome

- Confirmation performs exactly one target focus transaction. Promote the target in MRU only after a real focus event or a successful focus postcondition verifies that it actually obtained focus.
- First try the specific-WID private focus path; if it fails, permit one public AX raise/application-activation fallback and verify the same target afterward.
- If verification still fails, keep or restore the invoking window, close the list, show a short non-blocking “unable to switch” message, and do not update MRU. Diagnostic logs may record error categories but not window titles.
