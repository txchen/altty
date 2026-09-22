import ApplicationServices
import Foundation
import Testing
@testable import Altty

private final class ScriptedBatch: AXBatchReading, @unchecked Sendable {
    let patches: [WindowIdentity: WindowSemanticPatch]
    init(_ identities: [WindowIdentity], patch: WindowSemanticPatch) {
        patches = Dictionary(uniqueKeysWithValues: identities.map { ($0, patch) })
    }
    func readNext() -> AXEnrichmentBatch.Progress { .init(patches: patches, finished: true) }
}
private final class ReadScript: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    let steps: [WindowSemanticPatch]
    init(_ steps: [WindowSemanticPatch]) { self.steps = steps }
    var count: Int { lock.withLock { reads } }
    func batch(_ identities: [WindowIdentity]) -> any AXBatchReading {
        lock.withLock {
            defer { reads += 1 }
            return ScriptedBatch(identities, patch: steps[min(reads, steps.count - 1)])
        }
    }
}

@MainActor struct AccessibilityRecoveryTests {
    private var identity: WindowIdentity { .init(wid: 1, pid: 42, generation: 1) }
    private func failure(_ reason: AccessibilityReadFailure) -> WindowSemanticPatch {
        var patch = WindowSemanticPatch.unavailable; patch.readFailure = reason; return patch
    }
    @Test func transientFailureRecoversWithoutAnotherWindowNotification() async {
        let good = WindowSemanticPatch(title: .value("Recovered"), role: .value("AXWindow"), isTransient: .value(false))
        let script = ReadScript([failure(.temporarilyUnavailable), good])
        let adapter = SystemAccessibilityAdapter(isProcessRunning: { _ in true }, retryDelays: [.zero, .zero], batchFactory: script.batch)
        let engine = SwitcherEngine()
        _ = await engine.receiveInventory(.replaceActiveSpace(.init(activeSpaceIDs: [1], windows: [.init(wid: 1, pid: 42, frontToBackOrder: 0)])))
        await adapter.enrichments(for: [identity]) { identity, patch in
            _ = await engine.receiveInventory(.semanticsChanged(identity, patch))
        }
        #expect(script.count == 2)
        #expect(await engine.inventorySnapshot().windows.first?.title == "Recovered")
    }
    @Test func permanentErrorsDoNotRetryAndTransientRetriesEnd() async {
        for reason in [AccessibilityReadFailure.permanent, .invalidElement, .temporarilyUnavailable] {
            let script = ReadScript([failure(reason)])
            let adapter = SystemAccessibilityAdapter(isProcessRunning: { _ in true }, retryDelays: [.zero, .zero], batchFactory: script.batch)
            let patches = await adapter.enrichments(for: [identity])
            #expect(script.count == (reason == .temporarilyUnavailable ? 3 : 1))
            #expect(patches[identity]?.readFailure == reason)
        }
    }
    @Test func stopCancelsBackoffWithoutWaitingForTheTimer() async {
        let script = ReadScript([failure(.temporarilyUnavailable)])
        let adapter = SystemAccessibilityAdapter(isProcessRunning: { _ in true }, retryDelays: [.seconds(60)], batchFactory: script.batch)
        let task = Task { await adapter.enrichments(for: [identity]) }
        while script.count == 0 { await Task.yield() }
        // Allow the scheduler completion to enter backoff, then invalidate either phase.
        try? await Task.sleep(for: .milliseconds(10))
        adapter.cancelPendingEnrichment()
        #expect(await task.value.isEmpty)
        #expect(script.count == 1)
    }
    @Test func missingOptionalAttributesAreNotTreatedAsTimeouts() {
        let budget = AXReadBudget()
        budget.record(.attributeUnsupported)
        budget.record(.noValue)
        #expect(budget.failure == nil)
        budget.record(.cannotComplete)
        #expect(budget.failure == .temporarilyUnavailable)
        budget.record(.invalidUIElement)
        #expect(budget.failure == .invalidElement)
    }
}
