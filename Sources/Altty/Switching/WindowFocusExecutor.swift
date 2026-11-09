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

    nonisolated static func matches(_ observed: FocusedWindow?, target: WindowIdentity,
                        snapshot: WindowServerSnapshot?) -> Bool {
        guard let observed, observed.pid == target.pid else { return false }
        if observed.wid == target.wid { return true }
        guard let snapshot else { return false }
        let windows = snapshot.windows.filter { $0.pid == target.pid }
        guard windows.contains(where: { $0.wid == target.wid }) else { return false }
        var current = observed.wid
        var visited: Set<WindowID> = []
        while visited.insert(current).inserted,
              let window = windows.first(where: { $0.wid == current }),
              let parent = window.parentWID, parent != 0 {
            if parent == target.wid { return true }
            current = parent
        }
        return false
    }
}
