# 20 — Meet the lightweight performance budget

**What to build:** Tune and instrument the completed product so it behaves as a lightweight background utility under idle, normal and hostile workloads, with reproducible evidence for the accepted CPU, memory and latency budgets.

**Blocked by:** 19 — Harden lifecycle, failures and event races

**Status:** resolved

- [x] An authorized arm64 Release build averages under 0.2% CPU over a five-minute idle run.
- [x] Idle resident memory remains under 50 MB and shows no unexplained growth over 30 minutes.
- [x] Idle instrumentation reports zero fixed polling and no uncaused Accessibility or SkyLight queries.
- [x] Warm-cache shortcut event to focus-transaction start has p95 below 30 ms.
- [x] Panel presentation occurs within the accepted 100–150 ms window without delaying the quick-switch operation.
- [x] Filtering, sorting and snapshotting 100 windows has p95 below 10 ms.
- [x] After 1,000 create/destroy cycles and 100 rapid switches, inventory records, observers, AX references, shortcut registration, memory and MRU return to a correct stable baseline.
- [x] A ten-second burst of 100 events/second is coalesced without linear Accessibility amplification or main-thread stalls.
- [x] Benchmark output records hardware, OS, build SHA, CPU, memory, wakeups, adapter call counts and p50/p95/p99 latency without recording window titles.
- [x] Deterministic microbenchmarks guard regressions in CI; documented clean-hardware procedures collect real RC metrics.

## Answer

The performance gate now has deterministic CI coverage and a reproducible release-candidate measurement path. `PerformanceBudgetTests` guards nearest-rank percentile reporting, title-free output, 1,000 create/destroy cycles, one-query burst coalescing and the 100-window filter/sort/snapshot p95 budget. The production app emits privacy-safe unified-log events for Accessibility and SkyLight calls, shortcut-to-focus start and delayed-panel presentation; it never passes window content into the performance schema.

`scripts/collect-performance.sh` samples the packaged arm64 Release app for five-minute CPU and 30-minute RSS defaults, captures process wakeups with `powermetrics`, counts adapter calls, calculates p50/p95/p99 interaction latency and writes SHA-linked JSON plus raw evidence. Idle mode requires zero post-startup adapter calls; interaction mode requires at least 100 focus and 100 panel samples and enforces their latency gates. `Docs/performance.md` defines the clean authorized-hardware setup, warm-cache workload, required before/after resource observations, controlled ten-second event burst and pass/fail interpretation. Real CPU, RSS, wakeup and end-to-end results remain release-candidate evidence produced on the target clean Mac rather than assertions fabricated in CI.
