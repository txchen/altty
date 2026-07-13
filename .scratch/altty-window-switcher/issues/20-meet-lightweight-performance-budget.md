# 20 — Meet the lightweight performance budget

**What to build:** Tune and instrument the completed product so it behaves as a lightweight background utility under idle, normal and hostile workloads, with reproducible evidence for the accepted CPU, memory and latency budgets.

**Blocked by:** 19 — Harden lifecycle, failures and event races

**Status:** ready-for-agent

- [ ] An authorized arm64 Release build averages under 0.2% CPU over a five-minute idle run.
- [ ] Idle resident memory remains under 50 MB and shows no unexplained growth over 30 minutes.
- [ ] Idle instrumentation reports zero fixed polling and no uncaused Accessibility or SkyLight queries.
- [ ] Warm-cache shortcut event to focus-transaction start has p95 below 30 ms.
- [ ] Panel presentation occurs within the accepted 100–150 ms window without delaying the quick-switch operation.
- [ ] Filtering, sorting and snapshotting 100 windows has p95 below 10 ms.
- [ ] After 1,000 create/destroy cycles and 100 rapid switches, inventory records, observers, AX references, shortcut registration, memory and MRU return to a correct stable baseline.
- [ ] A ten-second burst of 100 events/second is coalesced without linear Accessibility amplification or main-thread stalls.
- [ ] Benchmark output records hardware, OS, build SHA, CPU, memory, wakeups, adapter call counts and p50/p95/p99 latency without recording window titles.
- [ ] Deterministic microbenchmarks guard regressions in CI; documented clean-hardware procedures collect real RC metrics.
