struct InventoryRefreshCoalescer: Sendable {
    private var pending: InventoryRefreshMode?

    mutating func request(_ mode: InventoryRefreshMode) {
        if mode == .replace || pending == nil { pending = mode }
    }

    mutating func takePending() -> InventoryRefreshMode? {
        defer { pending = nil }
        return pending
    }

    mutating func reset() { pending = nil }
}
