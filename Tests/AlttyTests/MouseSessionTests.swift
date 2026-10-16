import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Testing
@testable import Altty

struct MouseMovementTests {
    @Test func diagonalNormalizationOppositesAndSpeedPriority() {
        var move = MouseMovement(held: [13, 2])
        #expect(abs(hypot(move.direction.dx, move.direction.dy) - 1) < 0.00001)
        #expect(move.direction.dy < 0)
        move.held.formUnion([0, 1])
        #expect(move.direction == .zero)
        move.held.formUnion([32, 34])
        #expect(move.speed == .slow)
        move.held.remove(32)
        #expect(move.speed == .fast)
        move.held.remove(34)
        #expect(move.speed == .normal)
    }
    @Test func pointerProjectsToRealScreensIncludingNegativeOriginsAndGaps() {
        let screens = [CGRect(x: -100, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]
        #expect(MouseScreenGeometry.project(CGPoint(x: -50, y: 20), onto: screens) == CGPoint(x: -50, y: 20))
        #expect(MouseScreenGeometry.project(CGPoint(x: 20, y: 20), onto: screens) == CGPoint(x: -1, y: 20))
    }
    @Test func pickerCompletesImmediatelyAndBackspaceRestoresCandidates() {
        var picker = MouseHintPicker(count: 20)
        let index = picker.labels.firstIndex(where: { $0.count > 1 })!
        let label = picker.labels[index]
        #expect(picker.handle(.letter(label.first!)) == nil)
        _ = picker.handle(.backspace)
        #expect(picker.prefix.isEmpty)
        var result: Int?
        for letter in label { result = picker.handle(.letter(letter)) }
        #expect(result == index)
    }
}

struct NavigationKeyLedgerTests {
    @Test func exitInsideDownStillOwnsRepeatAndRelease() {
        let ledger = NavigationKeyLedger()
        var callbacks = 0
        let swallowed = ledger.press(13) { callbacks += 1; #expect(!ledger.isEmpty); return true }
        #expect(swallowed)
        #expect(ledger.press(13, isRepeat: true, active: false) { callbacks += 1; return false })
        #expect(ledger.release(13))
        #expect(callbacks == 1)
        #expect(ledger.isEmpty)
    }
    @Test func reentryCannotTurnAnOldHeldKeyIntoAnAction() {
        let ledger = NavigationKeyLedger()
        #expect(ledger.press(38) { true })
        var clicks = 0
        #expect(ledger.press(38) { clicks += 1; return true })
        #expect(clicks == 0)
        #expect(ledger.release(38))
        #expect(ledger.press(38) { clicks += 1; return true })
        #expect(clicks == 1)
    }
    @Test func passedDownAlwaysPassesRepeatAndUp() {
        let ledger = NavigationKeyLedger()
        #expect(!ledger.press(8) { false })
        #expect(!ledger.press(8, isRepeat: true) { true })
        #expect(!ledger.release(8))
        #expect(ledger.press(8, isRepeat: true) { Issue.record("Repeat acted"); return false })
    }
}

@MainActor private final class MouseTestTap: HintKeyboardTap {
    var currentFlags: CGEventFlags = []
    var handler: (@MainActor (HintTapEvent) -> Bool)?
    var failure: (@MainActor () -> Void)?
    let ledger = NavigationKeyLedger()
    func start(onEvent: @escaping @MainActor (HintTapEvent) -> Bool, onFailure: @escaping @MainActor () -> Void) -> Bool {
        handler = onEvent; failure = onFailure; return true
    }
    func stop() { handler = nil; failure = nil }
    @discardableResult func down(_ code: UInt16, text: String = "", flags: CGEventFlags = [], repeatKey: Bool = false) -> Bool {
        ledger.press(code, isRepeat: repeatKey, active: handler != nil) {
            handler?(.key(HintRawKeyEvent(kind: .keyDown, keyCode: code, flags: flags, characters: text))) ?? false
        }
    }
    func up(_ code: UInt16) {
        _ = ledger.release(code)
        _ = handler?(.key(HintRawKeyEvent(kind: .keyUp, keyCode: code, flags: [], characters: "")))
    }
}
@MainActor private final class MouseTestScanner: HintScanner {
    var completions: [@MainActor @Sendable (HintScanResult) -> Void] = []
    func scan(pid: pid_t, completion: @escaping @MainActor @Sendable (HintScanResult) -> Void) { completions.append(completion) }
}
@MainActor private final class MouseTestPointer: MousePointer {
    var position = CGPoint(x: 100, y: 100)
    var screens = [CGRect(x: 0, y: 0, width: 1000, height: 1000)]
    var clicks: [CGMouseButton] = []
    var moves: [CGPoint] = []
    func move(to point: CGPoint) { position = point; moves.append(point) }
    func click(_ button: CGMouseButton) { clicks.append(button) }
}
@MainActor private final class MouseTestHUD: MouseHUD {
    var status: String?
    func show(state: MouseHUDState, shortcut: String) { self.status = state.title }
    func hide() { status = nil }
}
@MainActor private final class MouseTestWorkspace: HintWorkspace {
    var frontmostPID: pid_t? = 42
    var doubleClickInterval: TimeInterval = 0.5
    var isSecureInputEnabled = false
    var activation: (@MainActor (pid_t?) -> Void)?
    func observeActivations(_ handler: @escaping @MainActor (pid_t?) -> Void) { activation = handler }
    func stopObservingActivations() { activation = nil }
    func beep() {}
}
@MainActor private final class MouseTestClock: HintClock {
    var now: TimeInterval = 100
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {}
}
@MainActor private final class MouseTestOverlay: HintOverlay {
    var items: [HintOverlayItem] = []
    func show(_ items: [HintOverlayItem]) { self.items = items }
    func hide() { items = [] }
}
@MainActor private struct MouseHarness {
    let tap = MouseTestTap()
    let scanner = MouseTestScanner()
    let pointer = MouseTestPointer()
    let hud = MouseTestHUD()
    let workspace = MouseTestWorkspace()
    let clock = MouseTestClock()
    let overlay = MouseTestOverlay()
    let controller: SystemMouseSessionController
    init() {
        controller = SystemMouseSessionController(scanner: scanner, overlay: overlay, tap: tap, pointer: pointer,
                                                  workspace: workspace, hud: hud, clock: clock)
        controller.setShortcut(ShortcutBinding(key: ShortcutKey(keyCode: 46, displayName: "M"), modifiers: [.option]))
        controller.toggleSession()
    }
    func tick(_ delta: TimeInterval = 0.01) { clock.now += delta; controller.tick() }
    func target() -> HintTarget {
        HintTarget(element: AXElementBox(element: AXUIElementCreateApplication(42)),
                   frame: CGRect(x: 300, y: 300, width: 20, height: 20), role: "AXButton", subrole: nil)
    }
}
@MainActor struct MouseSessionControllerTests {
    @Test func heldMotionStopsOnReleaseAndClicksOncePerPress() {
        let h = MouseHarness(); defer { h.controller.endSession() }
        h.tap.down(13); h.tick()
        #expect(h.pointer.position.y < 100)
        h.tap.up(13); let position = h.pointer.position; h.tick()
        #expect(h.pointer.position == position)
        h.tap.down(38); h.tap.down(38, repeatKey: true)
        #expect(h.pointer.clicks == [.left])
        h.tap.up(38); h.tap.down(38)
        h.tap.down(40)
        #expect(h.pointer.clicks == [.left, .left, .right])
        #expect(h.controller.isActive)
    }
    @Test func nestedPickerMovesWithoutClickAndRequiresFreshMovementPress() {
        let h = MouseHarness(); defer { h.controller.endSession() }
        h.tap.down(13); h.tap.down(3)
        h.scanner.completions[0](HintScanResult(targets: [h.target()], sawWebArea: false, visits: 1))
        h.tap.down(0, text: "a")
        #expect(h.pointer.position == CGPoint(x: 310, y: 310))
        #expect(h.pointer.clicks.isEmpty)
        h.tick(); #expect(h.pointer.moves.count == 1)
        h.tap.down(13, repeatKey: true); h.tick(); #expect(h.pointer.moves.count == 1)
        h.tap.up(13); h.tap.down(13); h.tick(); #expect(h.pointer.position.y < 310)
        h.tap.down(0, text: "a", repeatKey: true); h.tick()
        #expect(h.pointer.position.x == 310)
    }
    @Test func scanBuffersFreshLabelsAndDiscardsLateResults() {
        let h = MouseHarness(); defer { h.controller.endSession() }
        h.tap.down(3); h.tap.down(0, text: "a")
        h.scanner.completions[0](HintScanResult(targets: [h.target()], sawWebArea: false, visits: 1))
        #expect(h.pointer.moves.count == 1)
        h.tap.up(3); h.tap.down(3); h.tap.down(53)
        h.scanner.completions[1](HintScanResult(targets: [h.target()], sawWebArea: false, visits: 1))
        #expect(h.overlay.items.isEmpty)
        #expect(h.controller.isActive)
        h.tap.up(53); h.tap.down(53)
        #expect(!h.controller.isActive)
    }
    @Test func focusAndPhysicalClicksPersistButForeignChordExits() {
        let h = MouseHarness(); defer { h.controller.endSession() }
        h.workspace.activation?(99)
        #expect(h.tap.handler?(.mouseDown) == false)
        #expect(h.controller.isActive)
        h.tap.down(13); #expect(!h.tap.down(8, flags: .maskCommand))
        h.tick(); #expect(!h.controller.isActive)
        #expect(h.pointer.moves.isEmpty)
        #expect(h.hud.status == nil)
    }
    @Test func securityFailureAndQueuedTicksCannotRetainMotion() {
        let h = MouseHarness()
        h.tap.down(13); h.workspace.isSecureInputEnabled = true; h.tick()
        #expect(!h.controller.isActive)
        #expect(h.pointer.moves.isEmpty)
        h.workspace.isSecureInputEnabled = false; h.controller.toggleSession()
        h.tap.up(13); h.tap.down(13); h.tap.failure?(); h.tick()
        #expect(!h.controller.isActive)
        #expect(h.pointer.moves.isEmpty)
    }
    @Test func speedHUDAndStallClampRestoreNormalAfterRelease() {
        let h = MouseHarness(); defer { h.controller.endSession() }
        h.tap.down(34); #expect(h.hud.status == "Fast")
        h.tap.down(32); #expect(h.hud.status == "Slow")
        h.tap.up(32); #expect(h.hud.status == "Fast")
        h.tap.up(34); #expect(h.hud.status == "Normal")
        h.tap.down(2); h.tick(10)
        #expect(abs(h.pointer.position.x - 130) < 0.001)
    }
    @Test func modifiedReturnPassesThroughUnlessItIsTheRecordedMouseShortcut() {
        let h = MouseHarness()
        #expect(!h.tap.down(UInt16(kVK_Return), flags: .maskCommand))
        #expect(!h.controller.isActive)
        h.tap.up(UInt16(kVK_Return))
        h.controller.setShortcut(ShortcutBinding(key: ShortcutKey(keyCode: UInt32(kVK_Return), displayName: "Return"), modifiers: [.command]))
        h.controller.toggleSession()
        #expect(h.tap.down(UInt16(kVK_Return), flags: .maskCommand))
        #expect(!h.controller.isActive)
        h.controller.toggleSession()
        #expect(!h.controller.isActive)
    }
    @Test func samePIDActivationKeepsScanAndChangedShortcutEndsSession() {
        let h = MouseHarness()
        h.tap.down(3)
        h.workspace.activation?(42)
        h.scanner.completions[0](HintScanResult(targets: [h.target()], sawWebArea: false, visits: 1))
        #expect(h.overlay.items.count == 1)
        h.controller.setShortcut(ShortcutBinding(key: ShortcutKey(keyCode: 4, displayName: "H"), modifiers: [.option]))
        #expect(!h.controller.isActive)
        #expect(h.hud.status == nil)
    }
    @Test func sleepEndsStationaryOrMovingSessionsAndFractionalMotionSurvivesTicks() {
        let h = MouseHarness()
        h.tap.down(32)
        h.tap.down(2)
        h.tick(0.0001)
        h.tick(0.0001)
        #expect(h.pointer.position.x > 100)
        #expect(h.pointer.position.x < 101)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(!h.controller.isActive)
        #expect(h.hud.status == nil)
        let count = h.pointer.moves.count
        h.tick()
        #expect(h.pointer.moves.count == count)
    }
    @Test func shortcutExitsNestedHintsAndIgnoresCarbonEcho() {
        let h = MouseHarness()
        h.tap.down(3); h.tap.down(46, flags: .maskAlternate)
        #expect(!h.controller.isActive)
        h.controller.toggleSession(); #expect(!h.controller.isActive)
        h.clock.now += 0.4; h.controller.toggleSession(); #expect(h.controller.isActive)
        h.controller.setShortcut(nil); #expect(!h.controller.isActive)
    }
}
