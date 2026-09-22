import Foundation

/// A fixed coalescing window, one physical query, and one merged follow-up.
/// Cancellation invalidates results, never pretends a synchronous OS call stopped.
@MainActor
final class InventoryRefreshScheduler {
    typealias Query = @MainActor () async -> WindowServerSnapshot?
    typealias Apply = @MainActor (WindowServerSnapshot?, InventoryRefreshMode, UInt64) async -> Void

    private let delay: Duration
    private let query: Query
    private let apply: Apply
    private var pending = InventoryRefreshCoalescer()
    private var task: Task<Void, Never>?
    private(set) var revision: UInt64 = 0

    init(delay: Duration = .milliseconds(75), query: @escaping Query, apply: @escaping Apply) {
        self.delay = delay
        self.query = query
        self.apply = apply
    }

    func request(_ mode: InventoryRefreshMode) {
        if mode == .replace { revision &+= 1 }
        pending.request(mode)
        startIfNeeded()
    }

    func reset() {
        revision &+= 1
        pending.reset()
        // Retain the task/slot until the physical query (if any) finishes.
    }

    func isCurrent(_ revision: UInt64) -> Bool { revision == self.revision }

    private func startIfNeeded() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while true {
                try? await Task.sleep(for: self.delay)
                guard let mode = self.pending.takePending() else { break }
                let revision = self.revision
                let snapshot = await self.query()
                if self.isCurrent(revision) {
                    await self.apply(snapshot, mode, revision)
                }
            }
            self.task = nil
        }
    }
}
