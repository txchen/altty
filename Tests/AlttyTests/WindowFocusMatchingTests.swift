import Testing
@testable import Altty

struct WindowFocusMatchingTests {
    @Test func focusedChildBelongsToItsTargetWindow() {
        let target = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let missingSnapshot: WindowServerSnapshot? = nil
        let snapshot = WindowServerSnapshot(activeSpaceIDs: [1], windows: [
            .init(wid: 10, pid: 100, frontToBackOrder: 0, parentWID: 0),
            .init(wid: 11, pid: 100, frontToBackOrder: 1, parentWID: 10),
            .init(wid: 12, pid: 100, frontToBackOrder: 2, parentWID: 11),
            .init(wid: 20, pid: 100, frontToBackOrder: 3, parentWID: 0),
            .init(wid: 21, pid: 100, frontToBackOrder: 4, parentWID: 20),
            .init(wid: 30, pid: 100, frontToBackOrder: 5, parentWID: 31),
            .init(wid: 31, pid: 100, frontToBackOrder: 6, parentWID: 30),
            .init(wid: 40, pid: 200, frontToBackOrder: 7, parentWID: 10),
        ])
        let exactWithoutSnapshot = WindowFocusExecutor.matches(.init(wid: 10, pid: 100), target: target, snapshot: missingSnapshot)
        #expect(exactWithoutSnapshot)
        #expect(WindowFocusExecutor.matches(.init(wid: 11, pid: 100), target: target, snapshot: snapshot))
        #expect(WindowFocusExecutor.matches(.init(wid: 12, pid: 100), target: target, snapshot: snapshot))
        #expect(!WindowFocusExecutor.matches(.init(wid: 21, pid: 100), target: target, snapshot: snapshot))
        #expect(!WindowFocusExecutor.matches(.init(wid: 30, pid: 100), target: target, snapshot: snapshot))
        #expect(!WindowFocusExecutor.matches(.init(wid: 40, pid: 200), target: target, snapshot: snapshot))
        let childWithoutSnapshot = WindowFocusExecutor.matches(.init(wid: 11, pid: 100), target: target, snapshot: missingSnapshot)
        #expect(!childWithoutSnapshot)
        #expect(!WindowFocusExecutor.matches(nil, target: target, snapshot: snapshot))
    }
}
