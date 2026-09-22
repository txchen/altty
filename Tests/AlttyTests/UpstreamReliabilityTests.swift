import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import Altty

@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}

@MainActor
private final class SuspendedQueries {
    var calls = 0
    var active = 0
    var peak = 0
    var replies: [CheckedContinuation<WindowServerSnapshot?, Never>] = []
    func query() async -> WindowServerSnapshot? {
        calls += 1
        active += 1
        peak = max(peak, active)
        let result = await withCheckedContinuation { replies.append($0) }
        active -= 1
        return result
    }
    func finish(space: UInt64) {
        replies.removeFirst().resume(returning: .init(activeSpaceIDs: [space], windows: []))
    }
}

private final class BatchClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = ContinuousClock.now
    private(set) var enumerationCount = 0
    private var nextWID: WindowID = 10
    func now() -> ContinuousClock.Instant { lock.withLock { time } }
    func enumerate() { lock.withLock { enumerationCount += 1 } }
    func identify() -> WindowID {
        lock.withLock {
            time = time.advanced(by: .milliseconds(240))
            defer { nextWID += 10 }
            return nextWID
        }
    }
}

private actor DelayedInventory: InventoryAdapter {
    let initial: WindowInventorySnapshot
    var reply: CheckedContinuation<WindowInventorySnapshot, Never>?
    var isWaiting: Bool { reply != nil }
    init(_ initial: WindowInventorySnapshot) { self.initial = initial }
    func apply(_ event: InventoryEvent) -> [WindowIdentity] { [] }
    func snapshot() async -> WindowInventorySnapshot {
        await withCheckedContinuation { reply = $0 }
    }
    func finish() {
        reply?.resume(returning: initial)
        reply = nil
    }
}

@MainActor
struct UpstreamReliabilityTests {
    @Test func batchEnumeratesOnceAndResumesBeforeTheFirstUnfinishedSemanticRead() {
        let clock = BatchClock()
        let identities = (1...4).map { WindowIdentity(wid: WindowID($0 * 10), pid: 100, generation: 1) }
        let batch = AXEnrichmentBatch(
            identities: identities,
            enumerate: { _, _ in
                clock.enumerate()
                // Synthetic references only; injected functions perform no AX IPC.
                return (0..<4).map { _ in AXElementBox(element: AXUIElementCreateApplication(100)) }
            },
            identify: { _, _ in clock.identify() },
            read: { _, budget in
                #expect(!budget.expired)
                #expect(budget.remainingSeconds > 0.025)
                return .init(title: .value("Latest"), role: .value("AXWindow"), isTransient: .value(false))
            },
            makeBudget: { AXReadBudget(now: clock.now) }
        )
        var results: [WindowIdentity: WindowSemanticPatch] = [:]
        var slices = 0
        while slices < 10 {
            let progress = batch.readNext()
            slices += 1
            results.merge(progress.patches, uniquingKeysWith: { _, b in b })
            if progress.finished { break }
        }
        #expect(clock.enumerationCount == 1)
        #expect(slices == 5)
        #expect(Set(results.keys) == Set(identities))
        #expect(results.values.allSatisfy { $0.title == .value("Latest") })
    }

    @Test func invocationAwaitingSnapshotCannotCrossACompletedSpaceBoundary() async {
        let windows = (1...2).map { wid in
            SwitchableWindow(wid: WindowID(wid), pid: 100, generation: 1,
                title: "Fixture", titleIsStale: false, isMinimized: false, isFullscreen: false,
                applicationIsHidden: false, applicationIsFrontmost: true, bundleIdentifier: "fixture")
        }
        let snapshot = WindowInventorySnapshot(generation: 1, activeSpaceIDs: [1], windows: windows,
            liveIdentities: Set(windows.map(\.identity)), focusedWindow: windows[0].identity,
            frontmostApplicationPID: 100, exceptionForegroundContext: .unknown)
        let inventory = DelayedInventory(snapshot)
        let engine = SwitcherEngine(inventory: inventory)
        let invocation = Task { await engine.beginAllWindowsSwitch() }
        for _ in 0..<1_000 {
            if await inventory.isWaiting { break }
            await Task.yield()
        }
        #expect(await inventory.isWaiting)
        _ = engine.invalidateActiveSpace()
        engine.activeSpaceRefreshCompleted()
        await inventory.finish()
        #expect(await invocation.value.isEmpty)
        #expect(engine.activeSwitchSession == nil)
    }

    @Test func continuousRequestsMakeProgressWithoutOverlappingPhysicalQueries() async {
        let queries = SuspendedQueries()
        var applied: [UInt64] = []
        let scheduler = InventoryRefreshScheduler(delay: .milliseconds(1), query: queries.query) { snapshot, _, _ in
            applied.append(snapshot!.activeSpaceIDs[0])
        }
        scheduler.request(.reconcile)
        #expect(await eventually { queries.calls == 1 })
        for _ in 0..<1_000 { scheduler.request(.reconcile) }
        #expect(queries.calls == 1)
        queries.finish(space: 1)
        #expect(await eventually { queries.calls == 2 })
        // A continuous burst does not reject every answer until the event source goes quiet.
        #expect(applied == [1])
        queries.finish(space: 2)
        #expect(await eventually { applied == [1, 2] })
        #expect(queries.peak == 1)
        scheduler.reset()
    }

    @Test func replacementAndStopRejectLateAnswersAndRetainThePhysicalSlot() async {
        let queries = SuspendedQueries()
        var applied: [(UInt64, InventoryRefreshMode)] = []
        let scheduler = InventoryRefreshScheduler(delay: .milliseconds(1), query: queries.query) { snapshot, mode, _ in
            applied.append((snapshot!.activeSpaceIDs[0], mode))
        }
        scheduler.request(.replace)
        #expect(await eventually { queries.calls == 1 })
        scheduler.request(.replace)
        scheduler.request(.reconcile)
        queries.finish(space: 1)
        #expect(await eventually { queries.calls == 2 })
        #expect(applied.isEmpty)
        scheduler.reset()
        scheduler.request(.replace)
        queries.finish(space: 2)
        #expect(await eventually { queries.calls == 3 })
        #expect(applied.isEmpty)
        queries.finish(space: 3)
        #expect(await eventually { applied.count == 1 })
        #expect(applied.first?.0 == 3)
        #expect(applied.first?.1 == .replace)
        #expect(queries.peak == 1)
        scheduler.reset()
    }

    @Test func blockedAppCannotOccupyOtherAppsOrTheReservedFocusSlot() async {
        let scheduler = AccessibilityQueryScheduler(capacity: 3)
        let stalled = DispatchSemaphore(value: 0)
        let other = DispatchSemaphore(value: 0)
        let first = Task { await scheduler.run(pid: 10) {
            #expect(stalled.wait(timeout: .now() + 5) == .success)
            return 10
        } }
        #expect(await eventually { scheduler.runningJobCount == 1 })
        let siblings = (0..<20).map { _ in Task { await scheduler.run(pid: 10) { 11 } } }
        #expect(await eventually { scheduler.pendingJobCount == 20 })
        let second = Task { await scheduler.run(pid: 20) {
            #expect(other.wait(timeout: .now() + 5) == .success)
            return 20
        } }
        #expect(await eventually { scheduler.runningJobCount == 2 })
        let background = Task { await scheduler.run(pid: 30) { 30 } }
        #expect(await eventually { scheduler.pendingJobCount == 21 })
        let focus = await scheduler.run(pid: 40, priority: .interactive) { 40 }
        #expect(focus == 40)
        #expect(scheduler.runningJobCount == 2)
        scheduler.cancel(pid: 10)
        #expect(scheduler.pendingJobCount == 1)
        stalled.signal()
        other.signal()
        #expect(await first.value == nil)
        for sibling in siblings { #expect(await sibling.value == nil) }
        #expect(await second.value == 20)
        #expect(await background.value == 30)
        #expect(scheduler.runningJobCount == 0)
        #expect(scheduler.pendingJobCount == 0)
    }

    @Test func cancellationDoesNotPretendABlockedOSCallHasFinished() async {
        let scheduler = AccessibilityQueryScheduler(capacity: 2)
        let gate = DispatchSemaphore(value: 0)
        let old = Task { await scheduler.run(pid: 10) {
            #expect(gate.wait(timeout: .now() + 5) == .success)
            return 1
        } }
        #expect(await eventually { scheduler.runningJobCount == 1 })
        scheduler.cancel()
        let fresh = Task { await scheduler.run(pid: 10) { 2 } }
        #expect(await eventually { scheduler.pendingJobCount == 1 })
        #expect(scheduler.runningJobCount == 1)
        gate.signal()
        #expect(await old.value == nil)
        #expect(await fresh.value == 2)
        #expect(scheduler.runningJobCount == 0)
    }

    @Test func stableProcessIdentitySurvivesMissingPIDAndRejectsOldTermination() {
        var registry = WorkspaceIdentityRegistry<String>()
        registry.admit("original", pid: 42)
        #expect(registry.pid(for: "original") == 42)
        registry.admit("original", pid: -1)
        #expect(registry.pid(for: "original") == 42)
        registry.admit("reused", pid: 42)
        #expect(registry.terminate("original") == nil)
        #expect(registry.pid(for: "reused") == 42)
        #expect(registry.terminate("reused") == 42)
        #expect(registry.pid(for: "reused") == nil)
        #expect(!ProcessLiveness.isRunning(0))
        #expect(!ProcessLiveness.isRunning(-1))
        #expect(ProcessLiveness.isRunning(ProcessInfo.processInfo.processIdentifier))
    }

    @Test func spaceBoundaryImmediatelyBlocksInvocationAndLateFocusCompletions() async {
        let engine = SwitcherEngine()
        let windows = [WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                       WindowServerWindow(wid: 20, pid: 100, frontToBackOrder: 1)]
        _ = await engine.receiveInventory(.replaceActiveSpace(.init(activeSpaceIDs: [1], windows: windows)))
        for window in windows {
            _ = await engine.receiveInventory(.semanticsChanged(
                .init(wid: window.wid, pid: window.pid, generation: 1),
                .init(role: .value("AXWindow"), isMinimized: .value(false), isTransient: .value(false))
            ))
        }
        _ = await engine.beginAllWindowsSwitch()
        let session = engine.activeSwitchSession!
        _ = engine.confirmSwitch()
        #expect(!engine.invalidateActiveSpace().isEmpty)
        #expect(engine.activeSwitchSession == nil)
        for _ in 0..<100 { #expect(await engine.beginAllWindowsSwitch().isEmpty) }
        #expect(await engine.receiveSwitching(.focusCompleted(session.target.identity, succeeded: true),
                                             transactionID: session.transactionID).isEmpty)
        #expect(!engine.isCurrentFocusTransaction(session.transactionID))
        _ = await engine.receiveInventory(.replaceActiveSpace(.init(activeSpaceIDs: [2], windows: [])))
        engine.activeSpaceRefreshCompleted()
        #expect(await engine.beginAllWindowsSwitch().isEmpty)
        #expect(await engine.inventorySnapshot().activeSpaceIDs == [2])
    }

    @Test func selectionOnlyUpdatesKeepExistingViewsAndContentUpdatesTouchOneRow() {
        _ = NSApplication.shared
        func row(_ wid: WindowID, _ title: String) -> SwitcherPanelRow {
            .init(identity: .init(wid: wid, pid: 100, generation: 1), title: title,
                  applicationName: "Fixture", applicationBundlePath: nil,
                  isMinimized: false, applicationIsHidden: false, isFullscreen: false)
        }
        let a = row(10, "A"), b = row(20, "B"), c = row(30, "C")
        let panel = SwitcherPanelController()
        func state(_ rows: [SwitcherPanelRow], _ selection: WindowIdentity) -> SwitcherPanelState {
            .init(mode: .allWindows, shortcutDescription: "Option-Tab", rows: rows, selectedIdentity: selection)
        }
        panel.show(state: state([a, b, c], a.identity))
        let first = panel.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true)
        let second = panel.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true)
        for _ in 0..<100 {
            panel.update(state: state([a, b, c], b.identity))
            panel.update(state: state([a, b, c], a.identity))
        }
        #expect(panel.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) === first)
        #expect(panel.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) === second)
        panel.update(state: state([a, row(20, "Latest"), c], b.identity))
        #expect(panel.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) === first)
        #expect(panel.observedState.rows[1].title == "Latest")
        panel.update(state: state([a, c], c.identity))
        #expect(panel.observedState.selectedIdentity == c.identity)
        var selected: WindowIdentity?
        panel.onInteraction = { if case let .select(identity) = $0 { selected = identity } }
        panel.hover(row: 1)
        #expect(selected == c.identity)
        panel.dismiss()
    }
}
