import AppKit
import Testing
@testable import Altty

@MainActor private final class GestureRegistrar: HotKeyRegistrar {
    var bindings: [RegisteredHotKey] = []
    func register(_ hotKey: RegisteredHotKey) -> Bool { bindings.append(hotKey); return true }
    func unregister(id: UInt32) -> Bool { true }
}

@MainActor struct ShortcutGestureTests {
    @Test func twoPhysicalTapsKeepTheirOwnReleasesWhenMainCallbacksAreDelayed() {
        let history = ShortcutGestureHistory()
        let registrar = GestureRegistrar()
        let input = SystemInputAdapter(registrar: registrar, usesSystemMonitors: false, gestureHistory: history)
        var events: [ShortcutEvent] = []
        input.install { events.append($0) }
        #expect(input.setShortcutsEnabled(true) == .applied)
        let key = registrar.bindings[0]
        for time: UInt64 in [10, 30] {
            history.keyDown(keyCode: key.keyCode, modifiers: [.option], isRepeat: false, at: time)
            history.flagsChanged([], at: time + 10)
        }
        input.modifiersChanged([]) // both physical gestures completed before Carbon runs
        #expect(input.hotKeyPressed(id: key.id))
        #expect(input.hotKeyPressed(id: key.id))
        #expect(events == [.switcherPressed(.allWindows, .forward), .holdModifiersReleased,
                           .switcherPressed(.allWindows, .forward), .holdModifiersReleased])
        #expect(!input.hotKeyPressed(id: key.id)) // cannot replay a consumed physical press
    }

    @Test func heldNavigationDoesNotConfirmUntilItsLastQueuedPress() {
        let history = ShortcutGestureHistory()
        let registrar = GestureRegistrar()
        let input = SystemInputAdapter(registrar: registrar, usesSystemMonitors: false, gestureHistory: history)
        var events: [ShortcutEvent] = []
        input.install { events.append($0) }
        _ = input.setShortcutsEnabled(true)
        let key = registrar.bindings[0]
        history.keyDown(keyCode: key.keyCode, modifiers: [.option], isRepeat: false, at: 10)
        history.keyDown(keyCode: key.keyCode, modifiers: [.option], isRepeat: false, at: 20)
        history.flagsChanged([], at: 30)
        _ = input.hotKeyPressed(id: key.id)
        input.modifiersChanged([])
        #expect(events == [.switcherPressed(.allWindows, .forward)])
        _ = input.hotKeyPressed(id: key.id)
        #expect(events == [.switcherPressed(.allWindows, .forward), .switcherPressed(.allWindows, .forward), .holdModifiersReleased])
    }

    @Test func historyIgnoresTypingRepeatsAndIndividualModifierReleases() {
        let history = ShortcutGestureHistory()
        let modifiers: ShortcutModifiers = [.option, .control]
        history.configure([.init(id: 1, keyCode: 48, modifiers: modifiers.carbonValue)])
        for n in 0..<1_000 {
            history.keyDown(keyCode: 0, modifiers: [], isRepeat: false, at: UInt64(n))
            history.keyDown(keyCode: 48, modifiers: modifiers, isRepeat: true, at: UInt64(n))
        }
        #expect(history.retainedCount == 0)
        history.keyDown(keyCode: 48, modifiers: modifiers, isRepeat: false, at: 1_000)
        let press = history.claim(registration: 1)!
        history.flagsChanged([.option], at: 1_001)
        #expect(!history.canConfirm(press))
        history.flagsChanged([], at: 1_002)
        #expect(history.canConfirm(press))
        for n in 0..<1_000 { history.keyDown(keyCode: 48, modifiers: modifiers, isRepeat: false, at: UInt64(2_000 + n)) }
        #expect(history.retainedCount == 128)
        history.configure([])
        #expect(history.retainedCount == 0)
        #expect(history.claim(registration: 1) == nil)
    }
}
