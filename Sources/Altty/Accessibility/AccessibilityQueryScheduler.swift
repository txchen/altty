import Foundation

/// Remote AX IPC runs on Dispatch workers, never the Swift cooperative pool.
/// Local AX calls enter AppKit directly and must stay on the main actor.
/// Background scans leave one slot for focus, and no PID can occupy every slot.
@MainActor
final class AccessibilityQueryScheduler {
    enum Priority { case background, interactive }

    private final class Job {
        let id = UUID()
        let pid: ProcessID
        let priority: Priority
        var invalidated = false
        var start: (() -> Void)?
        let cancel: () -> Void

        init(pid: ProcessID, priority: Priority, cancel: @escaping () -> Void) {
            self.pid = pid
            self.priority = priority
            self.cancel = cancel
        }
    }

    private let capacity: Int
    private let perProcessLimit: Int
    private var waiting: [Job] = []
    private var running: [UUID: Job] = [:]

    var pendingJobCount: Int { waiting.count }
    var runningJobCount: Int { running.count }

    init(capacity: Int = 4, perProcessLimit: Int = 1) {
        precondition(capacity >= 2 && perProcessLimit > 0 && perProcessLimit < capacity)
        self.capacity = capacity
        self.perProcessLimit = perProcessLimit
    }

    func run<Value: Sendable>(
        pid: ProcessID,
        priority: Priority = .background,
        operation: @escaping @Sendable () -> Value
    ) async -> Value? {
        guard !Task.isCancelled else { return nil }
        if pid == ProcessInfo.processInfo.processIdentifier {
            // AX dispatches in-process actions synchronously into AppKit instead
            // of IPC. In particular AXRaise calls NSWindow.makeKeyAndOrderFront.
            return autoreleasepool(invoking: operation)
        }
        return await withCheckedContinuation { continuation in
            let job = Job(pid: pid, priority: priority) { continuation.resume(returning: nil) }
            let id = job.id
            job.start = { [self] in
                DispatchQueue.global(qos: priority == .interactive ? .userInitiated : .utility).async {
                    let value = autoreleasepool(invoking: operation)
                    Task { @MainActor in
                        let accepted = self.finish(id)
                        continuation.resume(returning: accepted ? value : nil)
                    }
                }
            }
            waiting.append(job)
            drain()
        }
    }

    func cancel(pid: ProcessID? = nil) {
        let cancelled = waiting.filter { pid == nil || $0.pid == pid }
        waiting.removeAll { pid == nil || $0.pid == pid }
        cancelled.forEach { $0.cancel() }
        for job in running.values where pid == nil || job.pid == pid { job.invalidated = true }
    }

    private func finish(_ id: UUID) -> Bool {
        guard let job = running.removeValue(forKey: id) else { return false }
        drain()
        return !job.invalidated
    }

    private func drain() {
        while running.count < capacity {
            let eligible: (Job) -> Bool = { [self] job in
                let siblings = running.values.filter { $0.pid == job.pid }.count
                let background = running.values.filter { $0.priority == .background }.count
                return siblings < perProcessLimit
                    && (job.priority == .interactive || background < capacity - 1)
            }
            guard let index = waiting.firstIndex(where: { $0.priority == .interactive && eligible($0) })
                ?? waiting.firstIndex(where: eligible) else { return }
            let job = waiting.remove(at: index)
            running[job.id] = job
            let start = job.start
            job.start = nil
            start?()
        }
    }
}
