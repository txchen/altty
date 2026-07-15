struct ShortcutPerformanceTracker: Sendable {
    private var sessionStartedAt: ContinuousClock.Instant?

    mutating func beginIfNeeded(at now: ContinuousClock.Instant = .now) {
        if sessionStartedAt == nil { sessionStartedAt = now }
    }

    mutating func cancel() { sessionStartedAt = nil }

    mutating func latency(
        to now: ContinuousClock.Instant = .now,
        clearStart: Bool = true
    ) -> UInt64? {
        guard let sessionStartedAt else { return nil }
        let duration = sessionStartedAt.duration(to: now).components
        let nanoseconds = UInt64(max(0, duration.seconds)) * 1_000_000_000
            + UInt64(max(0, duration.attoseconds / 1_000_000_000))
        if clearStart { self.sessionStartedAt = nil }
        return nanoseconds
    }
}
