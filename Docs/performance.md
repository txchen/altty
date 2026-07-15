# Performance acceptance

Altty has two performance gates. Deterministic microbenchmarks run with the normal test suite and protect the 100-window snapshot, lifecycle-baseline, report-privacy and burst-coalescing seams. Release-candidate measurements run only on clean, authorized Apple-silicon hardware because CPU, memory, wakeups, Accessibility and SkyLight behavior are system properties.

## Clean-hardware procedure

1. Use a supported macOS release on an otherwise idle Apple-silicon Mac. Record power source and display configuration with the result. Quit development tools, indexing work and unrelated menu-bar utilities.
2. Build the exact commit with `swift build -c release`, then package it with `CONFIGURATION=release ./scripts/build-app.sh`. Sign it with the release identity and grant that packaged app Accessibility permission. Do not measure a debug build.
3. Prime `sudo` with `sudo -v`; the collector uses `powermetrics` only for process wakeups and never launches Altty as root.
4. Launch a representative set of at least 100 windows once and exercise both shortcuts to warm Accessibility, SkyLight, icons and application metadata. Quit Altty afterward.
5. Run `ALTTY_PERFORMANCE_APP="$PWD/.build/Altty.app" ./scripts/collect-performance.sh`. The default `idle` mode collects five minutes of CPU and 30 minutes of RSS and fails on any post-startup adapter call. Do not cause workspace, window, display, permission or sleep/wake events.
6. Run a separate interaction collection with `ALTTY_PERFORMANCE_MODE=interaction ALTTY_MEMORY_SECONDS=600 ALTTY_IDLE_SECONDS=600`. Perform at least 100 quick switches and at least 100 delayed-panel sessions before it ends. Interaction mode requires both sample counts and applies latency gates; it permits the caused AX/SkyLight calls. Retain both runs' `report.json`, `process-samples.tsv`, `powermetrics.txt` and `performance.log` under distinct output directories.
7. For the hostile resource run, record Activity Monitor's memory graph and the Performance log before and after 1,000 create/destroy cycles plus 100 rapid switches. Observer subscriptions, shortcut registrations and AX references must return to their pre-run counts; RSS must return to its stable band and MRU must match the verified focus sequence. A result without all before/after observations fails.
8. Generate 1,000 real window semantic events over ten seconds with the controlled fixture application used for RC testing. Record raw fixture event count, Performance-log AX call count and a Time Profiler main-thread trace. AX calls must be sublinear to raw events, the UI must remain responsive, and the trace must contain no main-thread AX query stall. Keep all three artifacts; the value-type CI test alone is not sufficient evidence for this gate.
9. Run `./scripts/test.sh --filter PerformanceBudgetTests`, followed by the complete `./scripts/test.sh`, against the same SHA.

## Pass criteria

- Five-minute idle CPU average is below 0.2%; maximum idle RSS is below 50 MB; the 30-minute RSS series has no sustained unexplained growth.
- The idle Performance log has no adapter calls unless the procedure caused a corresponding system event. Altty owns no fixed inventory polling timer; the only repeating permission timer is scoped to the user actively visiting System Settings for an Accessibility grant.
- Warm `shortcut_to_focus_start` p95 is below 30 ms. `shortcut_to_panel_presentation` values are 100–150 ms and do not exist for quick-switch sessions that focus before the panel deadline.
- The deterministic 100-window workload p95 is below 10 ms.
- The lifecycle test returns inventory to empty after 1,000 create/destroy cycles. The lifecycle race suite covers observer, AX-reference, shortcut, focus-transaction and MRU cleanup; the interaction run confirms these remain stable after 100 real switches.
- A 1,000-event deterministic burst produces one pending adapter query. For the real ten-second 100-events/second run, compare adapter call counts and main-thread responsiveness; Accessibility calls must not scale linearly with raw events.

The JSON schema is deliberately closed over hardware, OS, SHA, resource totals, adapter categories and named latency distributions. Neither instrumentation nor the collector accepts or records window titles.
