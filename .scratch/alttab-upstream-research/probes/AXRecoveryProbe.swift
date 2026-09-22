import Foundation
@testable import Altty

@main struct AXRecoveryProbe {
    @MainActor static func main() async {
        let engine = SwitcherEngine()
        let snapshot = WindowServerSnapshot(activeSpaceIDs: [1], windows: [
            WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0)
        ])
        _ = await engine.receiveInventory(.replaceActiveSpace(snapshot))
        let identity = WindowIdentity(wid: 10, pid: 100, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(identity, .unavailable))
        let effects = await engine.receiveInventory(.reconcileActiveSpace(snapshot))
        print("after unavailable AX + unchanged WS reconciliation: windows=\(await engine.inventorySnapshot().windows.count), effects=\(effects.count)")
        print("AXFloatingWindow classified transient: \(WindowQualification.isTransient(role: "AXWindow", subrole: "AXFloatingWindow"))")
    }
}
