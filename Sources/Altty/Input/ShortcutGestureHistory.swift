import AppKit
import Foundation

/// Bounded, in-memory history of registered chords only. No typed text is retained.
/// The physical observer writes off-main; Carbon consumes on main.
final class ShortcutGestureHistory: @unchecked Sendable {
    struct Press: Sendable {
        let sequence: UInt64
        let registration: UInt32
        let time: UInt64
        let hold: ShortcutModifiers
        var release: UInt64?
        var claimed = false
        var reverseSteps = 0
    }
    private let lock = NSLock()
    private var bindings: [RegisteredHotKey] = []
    private var presses: [Press] = []
    private var sequence: UInt64 = 0
    private var previousModifiers: ShortcutModifiers = []
    private(set) var capacity = 128

    func configure(_ bindings: [RegisteredHotKey]) {
        lock.withLock { self.bindings = bindings; presses.removeAll(); previousModifiers = [] }
    }

    func reset() { lock.withLock { presses.removeAll(); previousModifiers = [] } }

    func keyDown(keyCode: UInt32, modifiers: ShortcutModifiers, isRepeat: Bool, at time: UInt64) {
        lock.withLock {
            guard !isRepeat, let binding = bindings.first(where: {
                $0.keyCode == keyCode && $0.modifiers == modifiers.carbonValue
            }) else { return }
            previousModifiers = modifiers
            sequence &+= 1
            presses.append(Press(sequence: sequence, registration: binding.id, time: time,
                                 hold: modifiers.intersection(.required)))
            ShortcutDiagnostics.record("physical_press registration=\(binding.id) sequence=\(sequence)")
            if presses.count > capacity { presses.removeFirst(presses.count - capacity) }
        }
    }

    func flagsChanged(_ modifiers: ShortcutModifiers, at time: UInt64) {
        lock.withLock {
            let shiftPressed = modifiers.contains(.shift) && !previousModifiers.contains(.shift)
            previousModifiers = modifiers
            if shiftPressed, let index = presses.indices.last,
               presses[index].release == nil, presses[index].time <= time,
               !modifiers.intersection(presses[index].hold).isEmpty {
                presses[index].reverseSteps += 1
            }
            for index in presses.indices where presses[index].release == nil && presses[index].time <= time {
                if modifiers.intersection(presses[index].hold).isEmpty { presses[index].release = time }
            }
        }
    }

    func claim(registration: UInt32) -> UInt64? {
        lock.withLock {
            guard let index = presses.firstIndex(where: { !$0.claimed && $0.registration == registration }) else { return nil }
            presses[index].claimed = true
            return presses[index].sequence
        }
    }

    /// Consume modifier-only navigation once, before confirming its gesture.
    func takeReverseSteps(after sequence: UInt64) -> Int {
        lock.withLock {
            guard let index = presses.firstIndex(where: { $0.sequence == sequence }) else { return 0 }
            let count = presses[index].reverseSteps
            presses[index].reverseSteps = 0
            return count
        }
    }

    func canConfirm(_ sequence: UInt64) -> Bool {
        lock.withLock {
            guard let press = presses.first(where: { $0.sequence == sequence }), let release = press.release else { return false }
            // Held Tab navigation may have several queued presses before ONE release.
            return !presses.contains { !$0.claimed && $0.time >= press.time && $0.time <= release }
        }
    }

    var retainedCount: Int { lock.withLock { presses.count } }
}

/// Owns a sleeping run loop so a main-thread stall cannot reorder physical facts.
/// This observer never consumes or reposts keyboard events.
final class ShortcutPhysicalMonitor: @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let condition = NSCondition()
        let history: ShortcutGestureHistory
        let onChange: @Sendable () -> Void
        let onFailure: @Sendable () -> Void
        var loop: CFRunLoop?
        var tap: CFMachPort?
        var started = false
        init(history: ShortcutGestureHistory, onChange: @escaping @Sendable () -> Void,
             onFailure: @escaping @Sendable () -> Void) {
            self.history = history; self.onChange = onChange; self.onFailure = onFailure
        }
        func publish(loop: CFRunLoop?, tap: CFMachPort?) {
            condition.lock()
            self.loop = loop; self.tap = tap; started = true
            condition.broadcast()
            condition.unlock()
        }
    }
    private let state: State

    init(history: ShortcutGestureHistory, onChange: @escaping @Sendable () -> Void,
         onFailure: @escaping @Sendable () -> Void) {
        state = State(history: history, onChange: onChange, onFailure: onFailure)
    }

    func start() -> Bool {
        let state = state
        let worker = Thread {
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, pointer in
                    guard let pointer else { return Unmanaged.passUnretained(event) }
                    let state = Unmanaged<State>.fromOpaque(pointer).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        state.history.reset()
                        state.onFailure()
                        return Unmanaged.passUnretained(event)
                    }
                    let flags = ShortcutModifiers(eventFlags: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
                    if type == .keyDown {
                        state.history.keyDown(keyCode: UInt32(event.getIntegerValueField(.keyboardEventKeycode)),
                            modifiers: flags, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                            at: event.timestamp)
                    } else if type == .flagsChanged {
                        state.history.flagsChanged(flags, at: event.timestamp)
                        state.onChange()
                    }
                    return Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(state).toOpaque()),
                  let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                state.publish(loop: nil, tap: nil)
                return
            }
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            state.publish(loop: loop, tap: tap)
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        worker.name = "Altty shortcut order"
        worker.qualityOfService = .userInteractive
        worker.start()
        state.condition.lock()
        defer { state.condition.unlock() }
        while !state.started { state.condition.wait() }
        return state.tap != nil
    }

    func stop() {
        state.condition.lock()
        let loop = state.loop
        let tap = state.tap
        state.loop = nil; state.tap = nil
        state.condition.unlock()
        state.history.reset()
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
                if let tap { CFMachPortInvalidate(tap) }
                CFRunLoopStop(loop)
            }
            CFRunLoopWakeUp(loop)
        }
    }
    deinit { stop() }
}
