import Testing
import AppKit
@testable import Altty

@Suite("Lightweight performance budget")
struct PerformanceBudgetTests {
    @Test("latency distributions use nearest-rank percentiles")
    func latencyDistribution() {
        let distribution = LatencyDistribution(samplesNanoseconds: Array(1...100).map(Int64.init))

        #expect(distribution.sampleCount == 100)
        #expect(distribution.p50Nanoseconds == 50)
        #expect(distribution.p95Nanoseconds == 95)
        #expect(distribution.p99Nanoseconds == 99)
    }

    @Test("repeated shortcut presses retain the original panel timing origin")
    func shortcutTimingOrigin() throws {
        let clock = ContinuousClock()
        let start = clock.now
        var tracker = ShortcutPerformanceTracker()
        tracker.beginIfNeeded(at: start)
        tracker.beginIfNeeded(at: start.advanced(by: .milliseconds(80)))

        let measuredPanelLatency = tracker.latency(
            to: start.advanced(by: .milliseconds(125)),
            clearStart: false
        )
        let measuredFocusLatency = tracker.latency(
            to: start.advanced(by: .milliseconds(140))
        )
        let panelLatency = try #require(measuredPanelLatency)
        let focusLatency = try #require(measuredFocusLatency)

        #expect(panelLatency == 125_000_000)
        #expect(focusLatency == 140_000_000)
        #expect(tracker.latency(to: start.advanced(by: .milliseconds(150))) == nil)
    }

    @Test("benchmark output contains required metadata without window titles")
    func privateContentFreeReport() throws {
        let report = PerformanceReport(
            hardwareModel: "Mac15,4",
            osVersion: "macOS 15.5 (24F74)",
            buildSHA: "0123456789abcdef",
            cpuAveragePercent: 0.12,
            residentMemoryBytes: 42_000_000,
            wakeups: 7,
            adapterCalls: .init(accessibility: 3, skyLight: 2),
            latencies: .init(
                shortcutToFocusStart: .init(samplesNanoseconds: [1, 2, 3]),
                shortcutToPanelPresentation: .init(samplesNanoseconds: [100, 125, 150]),
                filterSortSnapshot100: .init(samplesNanoseconds: [4, 5, 6])
            )
        )

        let data = try PerformanceReport.encoder.encode(report)
        let output = try #require(String(data: data, encoding: .utf8))
        #expect(output.contains("hardware_model"))
        #expect(output.contains("p95_nanoseconds"))
        #expect(!output.localizedCaseInsensitiveContains("window_title"))
        #expect(!output.contains("Secret document"))
    }

    @Test("one thousand inventory events return to a stable baseline")
    func inventoryLifecycleBaseline() async {
        let inventory = WindowInventory()
        _ = await inventory.apply(.replaceActiveSpace(.init(activeSpaceIDs: [1], windows: [])))
        let generation = await inventory.snapshot().generation

        for index in 1...1_000 {
            let identity = WindowIdentity(wid: WindowID(index), pid: 42, generation: generation)
            _ = await inventory.apply(.created(
                .init(wid: identity.wid, pid: identity.pid, frontToBackOrder: index),
                generation: generation
            ))
            _ = await inventory.apply(.destroyed(identity))
        }

        let snapshot = await inventory.snapshot()
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.focusedWindow == nil)
    }

    @Test(
        "a 100-window filter sort and snapshot workload stays below ten milliseconds p95",
        .enabled(if: ProcessInfo.processInfo.environment["ALTTY_RUN_PERFORMANCE_BUDGET"] == "1")
    )
    func hundredWindowMicrobenchmark() async {
        var samples: [Int64] = []
        samples.reserveCapacity(100)

        for iteration in 0..<100 {
            let inventory = WindowInventory()
            let windows = (1...100).map {
                WindowServerWindow(wid: WindowID($0), pid: ProcessID(($0 % 10) + 1), frontToBackOrder: $0)
            }
            let start = ContinuousClock.now
            let identities = await inventory.apply(.replaceActiveSpace(.init(
                activeSpaceIDs: [1],
                windows: windows
            )))
            for identity in identities {
                _ = await inventory.apply(.semanticsChanged(identity, .init(
                    title: .value("fixture-\(iteration)-\(identity.wid)"),
                    role: .value("AXWindow"),
                    isTransient: .value(false)
                )))
            }
            _ = await inventory.snapshot()
            samples.append(start.duration(to: .now).nanoseconds)
        }

        let distribution = LatencyDistribution(samplesNanoseconds: samples)
        #expect(distribution.p95Nanoseconds < 10_000_000)
    }

    @Test("burst requests coalesce to one adapter query")
    @MainActor
    func burstCoalescing() {
        var coalescer = InventoryRefreshCoalescer()
        let start = ContinuousClock.now
        for _ in 0..<1_000 { coalescer.request(.reconcile) }
        let elapsed = start.duration(to: .now).nanoseconds

        #expect(coalescer.takePending() == .reconcile)
        #expect(coalescer.takePending() == nil)
        #expect(elapsed < 10_000_000)

        coalescer.request(.reconcile)
        coalescer.request(.replace)
        coalescer.request(.reconcile)
        #expect(coalescer.takePending() == .replace)
    }

    @Test("one hundred rapid verified switches leave a stable session and MRU baseline")
    @MainActor
    func rapidSwitchBaseline() async throws {
        let inventory = WindowInventory()
        let windows = (1...3).map {
            WindowServerWindow(wid: WindowID($0), pid: 42, frontToBackOrder: $0)
        }
        let identities = await inventory.apply(.replaceActiveSpace(.init(
            activeSpaceIDs: [1],
            windows: windows
        )))
        for identity in identities {
            _ = await inventory.apply(.semanticsChanged(identity, .init(
                role: .value("AXWindow"),
                isTransient: .value(false)
            )))
        }
        let engine = SwitcherEngine(inventory: inventory)

        for _ in 0..<100 {
            _ = await engine.invokeAllWindowsSwitch(direction: .forward)
            let target = try #require(engine.activeSwitchSession?.target.identity)
            let transactionID = try #require(engine.activeSwitchSession?.transactionID)
            _ = engine.confirmSwitch()
            _ = await engine.receiveSwitching(
                .focusCompleted(target, succeeded: true),
                transactionID: transactionID
            )
            _ = await engine.receiveSwitching(
                .focusPostconditionObserved(.init(wid: target.wid, pid: target.pid)),
                transactionID: transactionID
            )
        }

        let snapshot = await inventory.snapshot()
        #expect(engine.activeSwitchSession == nil)
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows.first?.identity == snapshot.focusedWindow)
        #expect(Set(snapshot.windows.map(\.identity)).count == 3)
    }
}

private extension Duration {
    var nanoseconds: Int64 {
        let components = self.components
        return components.seconds * 1_000_000_000 + Int64(components.attoseconds / 1_000_000_000)
    }
}
