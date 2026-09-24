import Testing
@testable import Altty

/// Runs the production inventory, with one actor hop held at a controlled boundary.
private actor SuspendedSnapshotInventory: InventoryAdapter {
    let base = WindowInventory()
    private var shouldSuspend = false
    private var shouldSuspendFocus = false
    private var reached = false
    private var reachedWaiter: CheckedContinuation<Void, Never>?
    private var resumeSnapshot: CheckedContinuation<Void, Never>?

    func apply(_ event: InventoryEvent) async -> [WindowIdentity] {
        let result = await base.apply(event)
        if case .focused = event, shouldSuspendFocus {
            shouldSuspendFocus = false
            await pause()
        }
        return result
    }
    func arm() { shouldSuspend = true; reached = false }
    func armFocus() { shouldSuspendFocus = true; reached = false }
    func waitUntilSuspended() async {
        if reached { return }
        await withCheckedContinuation { reachedWaiter = $0 }
    }
    func resume() { resumeSnapshot?.resume(); resumeSnapshot = nil }
    func snapshot() async -> WindowInventorySnapshot {
        let value = await base.snapshot()
        if shouldSuspend {
            shouldSuspend = false
            await pause()
        }
        return value
    }
    private func pause() async {
        await withCheckedContinuation { continuation in
            resumeSnapshot = continuation
            reached = true
            reachedWaiter?.resume()
            reachedWaiter = nil
        }
    }
}

@MainActor
struct SwitcherReentrancyTests {
    private func fixture() async -> (SuspendedSnapshotInventory, SwitcherEngine, WindowServerSnapshot) {
        let inventory = SuspendedSnapshotInventory()
        let engine = SwitcherEngine(inventory: inventory)
        let server = WindowServerSnapshot(activeSpaceIDs: [1], windows: [
            WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
            WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
        ])
        _ = await engine.receiveInventory(.replaceActiveSpace(server))
        for (wid, pid): (UInt32, Int32) in [(10, 100), (20, 200)] {
            _ = await engine.receiveInventory(.semanticsChanged(
                WindowIdentity(wid: wid, pid: pid, generation: 1),
                WindowSemanticPatch(role: .value("AXWindow"), isTransient: .value(false))
            ))
        }
        return (inventory, engine, server)
    }

    @Test func inventoryRefreshCannotResurrectACompletedFocusAndBlockTheNextShortcut() async throws {
        let (inventory, engine, server) = await fixture()
        _ = await engine.beginAllWindowsSwitch()
        let session = try #require(engine.activeSwitchSession)
        _ = engine.confirmSwitch()
        _ = await engine.receiveSwitching(.focusCompleted(session.target.identity, succeeded: true),
                                         transactionID: session.transactionID)

        // A real inventory reconciliation overlaps the final AX focus readback.
        await inventory.arm()
        let refresh = Task { await engine.receiveInventory(.reconcileActiveSpace(server)) }
        await inventory.waitUntilSuspended()
        _ = await engine.receiveSwitching(.focusPostconditionObserved(
            FocusedWindow(wid: session.target.wid, pid: session.target.pid)),
            transactionID: session.transactionID)
        #expect(engine.activeSwitchSession == nil)
        await inventory.resume()
        _ = await refresh.value

        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.invokeAllWindowsSwitch(direction: .forward)
                == [.scheduleSwitcherPanel(delayMilliseconds: 100)])
        _ = engine.invalidateActiveSpace()
    }

    @Test func refreshCannotRollConfirmationBackToWaitingForRelease() async throws {
        let (inventory, engine, server) = await fixture()
        _ = await engine.beginAllWindowsSwitch()
        await inventory.arm()
        let refresh = Task { await engine.receiveInventory(.reconcileActiveSpace(server)) }
        await inventory.waitUntilSuspended()
        _ = engine.confirmSwitch()
        let committed = try #require(engine.activeSwitchSession)
        await inventory.resume()
        _ = await refresh.value
        #expect(engine.activeSwitchSession == committed)
        #expect(engine.activeSwitchSession?.phase == .focusing)
    }

    @Test func refreshCannotOverwriteNavigationOrANewerSession() async throws {
        let (inventory, engine, server) = await fixture()
        _ = await engine.beginAllWindowsSwitch()
        await inventory.arm()
        let refresh = Task { await engine.receiveInventory(.reconcileActiveSpace(server)) }
        await inventory.waitUntilSuspended()
        _ = engine.receiveSession(.navigate(.forward))
        let navigated = try #require(engine.activeSwitchSession)
        await inventory.resume()
        _ = await refresh.value
        #expect(engine.activeSwitchSession == navigated)

        await inventory.arm()
        let secondRefresh = Task { await engine.receiveInventory(.reconcileActiveSpace(server)) }
        await inventory.waitUntilSuspended()
        _ = engine.receiveSession(.cancel(.shortcutInterrupted))
        _ = await engine.beginAllWindowsSwitch()
        let replacement = try #require(engine.activeSwitchSession)
        #expect(replacement.transactionID != navigated.transactionID)
        await inventory.resume()
        _ = await secondRefresh.value
        #expect(engine.activeSwitchSession == replacement)
    }

    @Test func oldFocusReadbackCannotEndANewerSession() async throws {
        let (inventory, engine, _) = await fixture()
        _ = await engine.beginAllWindowsSwitch()
        let session = try #require(engine.activeSwitchSession)
        _ = engine.confirmSwitch()
        _ = await engine.receiveSwitching(.focusCompleted(session.target.identity, succeeded: true),
                                         transactionID: session.transactionID)
        await inventory.armFocus()
        let completion = Task {
            await engine.receiveSwitching(.focusPostconditionObserved(
                FocusedWindow(wid: session.target.wid, pid: session.target.pid)),
                transactionID: session.transactionID)
        }
        await inventory.waitUntilSuspended()
        _ = engine.invalidateActiveSpace()
        engine.activeSpaceRefreshCompleted()
        _ = await engine.beginAllWindowsSwitch()
        let replacement = try #require(engine.activeSwitchSession)
        await inventory.resume()
        #expect(await completion.value == [])
        #expect(engine.activeSwitchSession == replacement)
    }
}
