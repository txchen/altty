import Foundation

/// SkyLight selects the exact process/window; AX then orders that window inside
/// its owner's stack. Some apps acknowledge the former without changing key focus.
@MainActor
struct WindowFocusExecutor {
    let windowServer: any WindowServerAdapter
    let accessibility: any AccessibilityAdapter

    func focus(_ identity: WindowIdentity, isCurrent: () -> Bool = { true }) async -> Bool {
        guard isCurrent(), await windowServer.focus(identity), isCurrent() else { return false }
        await accessibility.raiseWindow(identity)
        return isCurrent()
    }
}
