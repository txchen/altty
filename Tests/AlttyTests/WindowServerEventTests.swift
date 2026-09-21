import Foundation
import Testing
@testable import Altty

private final class WindowEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [WindowServerInventoryEvent] = []
    func append(_ event: WindowServerInventoryEvent) { lock.withLock { events.append(event) } }
    func take() -> [WindowServerInventoryEvent] {
        lock.withLock {
            defer { events.removeAll() }
            return events
        }
    }
}

struct WindowServerEventTests {
    @Test @MainActor func focusBeforeDiscoveryIsValidatedAndBecomesTheNextSessionOrigin() async {
        let log = WindowEventLog()
        let stream = SkyLightEventContext(onEvent: log.append)
        let origin = WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0)
        let created = WindowServerWindow(wid: 20, pid: 100, frontToBackOrder: 1)
        let engine = SwitcherEngine()
        _ = await engine.receiveInventory(.replaceActiveSpace(.init(activeSpaceIDs: [1], windows: [origin])))
        stream.setKnownWindows([origin], generation: 1)
        stream.publish(rawEvent: 811, wid: 20)
        stream.publish(rawEvent: 808, wid: 20)
        #expect(log.take() == [.created(20), .focusNeedsReconciliation])
        _ = await engine.receiveInventory(.reconcileActiveSpace(.init(activeSpaceIDs: [1], windows: [origin, created])))
        stream.setKnownWindows([origin, created], generation: 1)
        let targetIdentity = WindowIdentity(wid: 20, pid: 100, generation: 1)
        let events = log.take()
        #expect(events == [.focused(targetIdentity)])
        for event in events {
            if case let .focused(identity) = event { _ = await engine.receiveInventory(.focused(identity)) }
        }
        for window in [origin, created] {
            _ = await engine.receiveInventory(.semanticsChanged(
                .init(wid: window.wid, pid: window.pid, generation: 1),
                .init(role: .value("AXWindow"), isMinimized: .value(false), isTransient: .value(false))
            ))
        }
        let snapshot = await engine.inventorySnapshot()
        #expect(snapshot.windows.map(\.wid) == [20, 10])
        _ = await engine.beginAllWindowsSwitch()
        #expect(engine.activeSwitchSession?.origin == targetIdentity)
        #expect(engine.activeSwitchSession?.target.wid == 10)
    }

    @Test func obsoleteFocusIsNotReplayedAfterNewerFocusDestructionSpaceChangeOrStop() {
        for invalidation in ["newer", "destroyed", "space", "stop", "absent"] {
            let log = WindowEventLog()
            let stream = SkyLightEventContext(onEvent: log.append)
            let known = WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0)
            stream.setKnownWindows([known], generation: 1)
            stream.publish(rawEvent: 808, wid: 20)
            switch invalidation {
            case "newer": stream.publish(rawEvent: 808, wid: 10)
            case "destroyed": stream.publish(rawEvent: 804, wid: 20)
            case "space": stream.publish(rawEvent: 1401, wid: 0)
            case "stop": stream.setEnabled(false); stream.setEnabled(true)
            default: stream.setKnownWindows([known], generation: 1)
            }
            _ = log.take()
            stream.setKnownWindows([known, .init(wid: 20, pid: 200, frontToBackOrder: 1)], generation: 2)
            #expect(log.take().isEmpty, "Obsolete event survived \(invalidation)")
        }
    }
}
