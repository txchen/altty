import Foundation
import Testing
@testable import Altty

private final class ObservationLog: @unchecked Sendable {
    struct Snapshot {
        var active: Set<ProcessID> = []
        var creations: [ProcessID: Int] = [:]
        var invalidations: [ProcessID: Int] = [:]
        var usedMainThread = false
    }
    private let lock = NSLock()
    private var state = Snapshot()
    var snapshot: Snapshot { lock.withLock { state } }
    func created(_ pid: ProcessID) {
        lock.withLock {
            state.active.insert(pid)
            state.creations[pid, default: 0] += 1
            state.usedMainThread = state.usedMainThread || Thread.isMainThread
        }
    }
    func invalidated(_ pid: ProcessID) {
        lock.withLock {
            state.active.remove(pid)
            state.invalidations[pid, default: 0] += 1
            state.usedMainThread = state.usedMainThread || Thread.isMainThread
        }
    }
}

private final class TestObservation: AccessibilityObservationRegistration {
    let pid: ProcessID
    let log: ObservationLog
    init(pid: ProcessID, log: ObservationLog) {
        self.pid = pid
        self.log = log
        log.created(pid)
    }
    func invalidate() { log.invalidated(pid) }
}

// Explicit system-adapter seam: synthetic IPC registrations, real background run loop.
struct AccessibilityObservationTests {
    @Test @MainActor func terminatedPIDCanBeObservedAgainAndStoppingReleasesAllRegistrations() async {
        let log = ObservationLog()
        let worker = AccessibilityObservationWorker { pid, _ in TestObservation(pid: pid, log: log) }
        let adapter = SystemAccessibilityAdapter(observationWorker: worker)
        adapter.startMonitoringInventory { _ in }
        let fixturePID: ProcessID = 1_000_000
        adapter.observeApplication(pid: fixturePID)
        adapter.observeApplication(pid: fixturePID)
        await worker.flush()
        #expect(log.snapshot.creations[fixturePID] == 1)
        adapter.stopObservingApplication(pid: fixturePID)
        await worker.flush()
        #expect(!log.snapshot.active.contains(fixturePID))
        adapter.observeApplication(pid: fixturePID)
        await worker.flush()
        #expect(log.snapshot.creations[fixturePID] == 2)
        adapter.stopMonitoringInventory()
        await worker.flush()
        #expect(log.snapshot.active.isEmpty)
        #expect(log.snapshot.invalidations[fixturePID] == 2)
        #expect(!log.snapshot.usedMainThread)
    }

    @Test @MainActor func blockedRegistrationDoesNotBlockMainActorAndRemovalStillCleansUp() async {
        let log = ObservationLog()
        let gate = DispatchSemaphore(value: 0)
        let (starts, continuation) = AsyncStream<Void>.makeStream()
        let worker = AccessibilityObservationWorker { pid, _ in
            continuation.yield(())
            // Safety bound makes a failing implementation finish rather than hang the suite.
            let completed = gate.wait(timeout: .now() + 2)
            #expect(completed == .success)
            return TestObservation(pid: pid, log: log)
        }
        worker.observe(pid: 42) { _ in }
        var iterator = starts.makeAsyncIterator()
        _ = await iterator.next()
        // Executing this MainActor continuation while registration is blocked proves isolation.
        #expect(log.snapshot.active.isEmpty)
        worker.remove(pid: 42)
        gate.signal()
        await worker.flush()
        #expect(log.snapshot.creations[42] == 1)
        #expect(log.snapshot.invalidations[42] == 1)
        #expect(log.snapshot.active.isEmpty)
        #expect(!log.snapshot.usedMainThread)
        continuation.finish()
    }

    @Test func repeatedProcessChurnReturnsObserversToBaseline() async {
        let log = ObservationLog()
        let worker = AccessibilityObservationWorker { pid, _ in TestObservation(pid: pid, log: log) }
        for pid: ProcessID in 1...1_000 {
            worker.observe(pid: pid) { _ in }
            worker.remove(pid: pid)
        }
        await worker.flush()
        #expect(log.snapshot.active.isEmpty)
        #expect(log.snapshot.invalidations.count == 1_000)
        #expect(!log.snapshot.usedMainThread)
    }
}
