import Foundation

// This system seam owns registrations and callbacks on one sleeping run loop.
// No AX request, including registration or callback enrichment, runs on MainActor.
protocol AccessibilityObservationRegistration: AnyObject {
    func invalidate()
}

final class AccessibilityObservationWorker: @unchecked Sendable {
    typealias Factory = @Sendable (
        ProcessID, @escaping @Sendable (AccessibilityInventoryEvent) -> Void
    ) -> (any AccessibilityObservationRegistration)?

    // Accessed exclusively on the worker's run loop, including destruction.
    private final class State: @unchecked Sendable {
        var registrations: [ProcessID: any AccessibilityObservationRegistration] = [:]
        func removeAll() {
            registrations.values.forEach { $0.invalidate() }
            registrations.removeAll()
        }
    }

    private final class Startup: @unchecked Sendable {
        let condition = NSCondition()
        var runLoop: CFRunLoop?
        func publish(_ loop: CFRunLoop) {
            condition.lock()
            runLoop = loop
            condition.signal()
            condition.unlock()
        }
        func wait() -> CFRunLoop {
            condition.lock()
            defer { condition.unlock() }
            while runLoop == nil { condition.wait() }
            return runLoop!
        }
    }

    private let runLoop: CFRunLoop
    private let state = State()
    private let factory: Factory

    init(factory: @escaping Factory) {
        self.factory = factory
        let startup = Startup()
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()!
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)!
            CFRunLoopAddSource(loop, keepAlive, .defaultMode)
            startup.publish(loop)
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, keepAlive, .defaultMode)
        }
        thread.name = "Altty Accessibility observations"
        thread.qualityOfService = .userInitiated
        thread.start()
        // Only waits for run-loop creation; never waits for another process or AX.
        runLoop = startup.wait()
    }

    deinit {
        let state = state
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            state.removeAll()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    func observe(
        pid: ProcessID,
        onEvent: @escaping @Sendable (AccessibilityInventoryEvent) -> Void,
        onFailure: @escaping @Sendable () -> Void = {}
    ) {
        perform { [state, factory] in
            guard state.registrations[pid] == nil else { return }
            guard let registration = factory(pid, onEvent) else {
                onFailure()
                return
            }
            state.registrations[pid] = registration
        }
    }

    func remove(pid: ProcessID) {
        perform { [state] in state.registrations.removeValue(forKey: pid)?.invalidate() }
    }

    func removeAll() { perform { [state] in state.removeAll() } }

    // Barrier used by system-adapter tests; production never waits for AX work.
    func flush() async {
        await withCheckedContinuation { continuation in
            perform { continuation.resume() }
        }
    }

    private func perform(_ operation: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            autoreleasepool { operation() }
        }
        CFRunLoopWakeUp(runLoop)
    }
}
