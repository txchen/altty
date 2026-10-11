import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import Altty

@MainActor
private final class FakeScanner: HintScanner {
    var requests: [(pid: pid_t, completion: @MainActor @Sendable (HintScanResult) -> Void)] = []

    func scan(pid: pid_t, completion: @escaping @MainActor @Sendable (HintScanResult) -> Void) {
        requests.append((pid, completion))
    }

    func finish(_ index: Int, with targets: [HintTarget]) {
        requests[index].completion(HintScanResult(targets: targets, sawWebArea: false, visits: targets.count))
    }
}

@MainActor
private final class FakeOverlay: HintOverlay {
    var shown: [[HintOverlayItem]] = []
    var hides = 0

    func show(_ items: [HintOverlayItem]) { shown.append(items) }
    func hide() { hides += 1 }
}

@MainActor
private final class FakeTap: HintKeyboardTap {
    var startSucceeds = true
    var currentFlags: CGEventFlags = []
    private(set) var starts = 0
    private(set) var stops = 0
    private var onEvent: (@MainActor (HintTapEvent) -> Bool)?
    private var onFailure: (@MainActor () -> Void)?

    var isRunning: Bool { onEvent != nil }

    func start(
        onEvent: @escaping @MainActor (HintTapEvent) -> Bool,
        onFailure: @escaping @MainActor () -> Void
    ) -> Bool {
        starts += 1
        guard startSucceeds else { return false }
        self.onEvent = onEvent
        self.onFailure = onFailure
        return true
    }

    func stop() {
        stops += 1
        onEvent = nil
        onFailure = nil
    }

    func send(_ event: HintTapEvent) -> Bool {
        onEvent?(event) ?? false
    }

    func type(_ text: String) {
        for character in text { _ = send(.key(HintRawKeyEvent(kind: .keyDown, keyCode: 0, flags: [], characters: String(character)))) }
    }

    func press(_ keyCode: Int, flags: CGEventFlags = []) -> Bool {
        send(.key(HintRawKeyEvent(kind: .keyDown, keyCode: UInt16(keyCode), flags: flags, characters: "")))
    }

    func fail() { onFailure?() }
}

@MainActor
private final class FakePerformer: HintActionPerformer {
    var performed: [(action: HintAction, frame: CGRect)] = []

    func perform(_ action: HintAction, on target: HintTarget) {
        performed.append((action, target.frame))
    }
}

@MainActor
private final class FakeWorkspace: HintWorkspace {
    var frontmostPID: pid_t? = 42
    let doubleClickInterval: TimeInterval = 0.5
    var beeps = 0
    private var activation: (@MainActor () -> Void)?

    var isObserving: Bool { activation != nil }

    func observeActivations(_ handler: @escaping @MainActor () -> Void) { activation = handler }
    func stopObservingActivations() { activation = nil }
    func beep() { beeps += 1 }
    func activateAnotherApplication() { activation?() }
}

@MainActor
private final class FakeClock: HintClock {
    var now: TimeInterval = 100
    var scheduled: [(delay: TimeInterval, work: @MainActor () -> Void)] = []

    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        scheduled.append((delay, work))
    }

    func fireAll() {
        let pending = scheduled
        scheduled = []
        for entry in pending { entry.work() }
    }
}

@MainActor
private struct Harness {
    let scanner = FakeScanner()
    let overlay = FakeOverlay()
    let tap = FakeTap()
    let performer = FakePerformer()
    let workspace = FakeWorkspace()
    let clock = FakeClock()
    let controller: SystemHintSessionController

    static let shortcut = ShortcutBinding(
        key: ShortcutKey(keyCode: UInt32(kVK_ANSI_F), displayName: "F"),
        modifiers: [.control, .option, .command]
    )
    static let shortcutFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    init() {
        controller = SystemHintSessionController(
            scanner: scanner, overlay: overlay, tap: tap,
            performer: performer, workspace: workspace, clock: clock
        )
        controller.setShortcut(Self.shortcut)
    }

    static func target(_ index: Int, role: String = "AXLink") -> HintTarget {
        HintTarget(
            element: AXElementBox(element: AXUIElementCreateApplication(42)),
            frame: CGRect(x: 10, y: CGFloat(index) * 30, width: 20, height: 20),
            role: role,
            subrole: nil
        )
    }

    static func targets(_ count: Int, role: String = "AXLink") -> [HintTarget] {
        (0..<count).map { target($0, role: role) }
    }
}

@MainActor
struct HintSessionControllerTests {
    @Test func aSessionCapturesKeysBeforeScanningTheFrontmostApp() {
        let harness = Harness()
        harness.controller.toggleSession()
        #expect(harness.tap.isRunning)
        #expect(harness.workspace.isObserving)
        #expect(harness.scanner.requests.map(\.pid) == [42])
        harness.scanner.finish(0, with: Harness.targets(2))
        #expect(harness.overlay.shown.last?.map(\.label) == ["a", "s"])
        #expect(harness.overlay.shown.last?.first?.frame == Harness.target(0).frame)
    }

    @Test func aScanFromAnEndedSessionIsDiscarded() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.controller.toggleSession()
        #expect(!harness.tap.isRunning)
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(3))
        #expect(harness.overlay.shown.isEmpty)
        harness.scanner.finish(1, with: Harness.targets(1))
        #expect(harness.overlay.shown.last?.map(\.label) == ["a"])
        #expect(harness.controller.isActive)
    }

    @Test func zeroTargetsEndTheSessionWithABeep() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: [])
        #expect(!harness.controller.isActive)
        #expect(!harness.tap.isRunning)
        #expect(!harness.workspace.isObserving)
        #expect(harness.workspace.beeps == 1)
        #expect(harness.overlay.shown.isEmpty)
    }

    @Test func aFailedTapStartEndsBeforeScanning() {
        let harness = Harness()
        harness.tap.startSucceeds = false
        harness.controller.toggleSession()
        #expect(!harness.controller.isActive)
        #expect(harness.scanner.requests.isEmpty)
        #expect(harness.workspace.beeps == 1)
    }

    @Test func keysTypedDuringTheScanAreReplayedInOrder() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.tap.type("l")
        harness.tap.type("s")
        #expect(harness.tap.press(kVK_Return))
        harness.scanner.finish(0, with: Harness.targets(10, role: "AXButton"))
        #expect(harness.performer.performed.map(\.action) == [.defaultAction])
        #expect(harness.performer.performed.first?.frame == Harness.target(9).frame)
        #expect(!harness.controller.isActive)
        #expect(harness.overlay.shown.isEmpty)
    }

    @Test func typingRedrawsAndEnterPerformsTheDefaultAction() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(3, role: "AXButton"))
        harness.tap.type("s")
        #expect(harness.overlay.shown.last?.filter(\.isSelected).map(\.label) == ["s"])
        #expect(!harness.tap.send(.key(HintRawKeyEvent(kind: .keyUp, keyCode: 1, flags: [], characters: ""))))
        #expect(harness.tap.press(kVK_Return))
        #expect(harness.performer.performed.map(\.action) == [.defaultAction])
        #expect(!harness.controller.isActive)
        #expect(!harness.tap.isRunning)
    }

    @Test func enterTwiceDoubleClicksAndTheWindowTimesOut() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(2))
        harness.tap.type("a")
        #expect(harness.tap.press(kVK_Return))
        #expect(harness.controller.isActive)
        #expect(harness.clock.scheduled.map(\.delay) == [0.5])
        #expect(harness.tap.press(kVK_Return))
        #expect(harness.performer.performed.map(\.action) == [.defaultAction, .secondClickOfDouble])
        #expect(!harness.controller.isActive)
        harness.clock.fireAll()

        harness.controller.toggleSession()
        harness.scanner.finish(1, with: Harness.targets(2))
        harness.tap.type("a")
        _ = harness.tap.press(kVK_Return)
        harness.clock.fireAll()
        #expect(!harness.controller.isActive)
        #expect(harness.performer.performed.count == 3)
    }

    @Test func anotherKeyAfterTheFirstClickPassesThrough() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(2))
        harness.tap.type("a")
        _ = harness.tap.press(kVK_Return)
        #expect(!harness.tap.press(kVK_Escape))
        #expect(!harness.controller.isActive)
    }

    @Test func theShortcutChordEndsTheSessionAndSuppressesItsCarbonEcho() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(2))
        #expect(harness.tap.press(kVK_ANSI_F, flags: Harness.shortcutFlags))
        #expect(!harness.controller.isActive)
        harness.clock.now += 0.1
        harness.controller.toggleSession()
        #expect(!harness.controller.isActive)
        #expect(harness.tap.starts == 1)
        harness.clock.now += 0.25
        harness.controller.toggleSession()
        #expect(harness.controller.isActive)
    }

    @Test func theShortcutChordAlsoEndsAScanInProgress() {
        let harness = Harness()
        harness.controller.toggleSession()
        #expect(harness.tap.press(kVK_ANSI_F, flags: Harness.shortcutFlags))
        #expect(!harness.controller.isActive)
        harness.scanner.finish(0, with: Harness.targets(2))
        #expect(harness.overlay.shown.isEmpty)
    }

    @Test func aFrontmostApplicationChangeEndsTheSession() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(2))
        harness.workspace.activateAnotherApplication()
        #expect(!harness.controller.isActive)
        #expect(!harness.tap.isRunning)
        #expect(harness.overlay.hides > 0)
    }

    @Test func aMouseDownEndsTheSessionAndPassesThrough() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(2))
        #expect(!harness.tap.send(.mouseDown))
        #expect(!harness.controller.isActive)
    }

    @Test func otherChordsEndAndPassThrough() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(2))
        #expect(!harness.tap.press(kVK_ANSI_C, flags: .maskCommand))
        #expect(!harness.controller.isActive)
    }

    @Test func tapFailureAndClearingTheShortcutEndTheSession() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.tap.fail()
        #expect(!harness.controller.isActive)
        harness.controller.toggleSession()
        #expect(harness.controller.isActive)
        harness.controller.setShortcut(nil)
        #expect(!harness.controller.isActive)
        #expect(!harness.tap.isRunning)
    }

    @Test func controlTapHoversTheSelection() {
        let harness = Harness()
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(2))
        harness.tap.type("s")
        let control = HintRawKeyEvent(kind: .flagsChanged, keyCode: UInt16(kVK_Control), flags: .maskControl, characters: "")
        let release = HintRawKeyEvent(kind: .flagsChanged, keyCode: UInt16(kVK_Control), flags: [], characters: "")
        #expect(!harness.tap.send(.key(control)))
        #expect(!harness.tap.send(.key(release)))
        #expect(harness.performer.performed.map(\.action) == [.hover])
        #expect(!harness.controller.isActive)
    }

    @Test func theShortcutsOwnHeldControlIsNotATap() {
        let harness = Harness()
        harness.tap.currentFlags = Harness.shortcutFlags
        harness.controller.toggleSession()
        harness.scanner.finish(0, with: Harness.targets(2))
        harness.tap.type("s")
        for flags: CGEventFlags in [[.maskControl], []] {
            _ = harness.tap.send(.key(HintRawKeyEvent(kind: .flagsChanged, keyCode: 0, flags: flags, characters: "")))
        }
        #expect(harness.performer.performed.isEmpty)
        #expect(harness.controller.isActive)
    }
}
