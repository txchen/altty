import AppKit
import CoreGraphics

enum HintTapEvent: Equatable, Sendable {
    case key(HintRawKeyEvent)
    case mouseDown
}

@MainActor
protocol HintKeyboardTap: AnyObject {
    /// `onEvent` returns whether to swallow the event; `onFailure` reports a tap
    /// the system disabled. Missed releases make continuing unsafe.
    func start(
        onEvent: @escaping @MainActor (HintTapEvent) -> Bool,
        onFailure: @escaping @MainActor () -> Void
    ) -> Bool
    func stop()
    /// The modifiers held right now, so a session knows what was already down.
    var currentFlags: CGEventFlags { get }
}

/// An active session tap on the main run loop. The key-up of every swallowed
/// key-down is swallowed too, as are key repeats; events Altty posted itself
/// pass untouched. Normal stop drains owned releases for at most two seconds.
@MainActor
final class CoreGraphicsHintKeyboardTap: HintKeyboardTap {
    private static let keyEvents: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    private static let mouseEvents: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var onEvent: (@MainActor (HintTapEvent) -> Bool)?
    private var onFailure: (@MainActor () -> Void)?
    private var ledger = NavigationKeyLedger()
    private var drainTimer: Timer?

    var currentFlags: CGEventFlags { CGEventSource.flagsState(.combinedSessionState) }

    func start(
        onEvent: @escaping @MainActor (HintTapEvent) -> Bool,
        onFailure: @escaping @MainActor () -> Void
    ) -> Bool {
        drainTimer?.invalidate()
        drainTimer = nil
        self.onEvent = onEvent
        self.onFailure = onFailure
        if port != nil { return true }
        let mask = (Self.keyEvents + Self.mouseEvents).reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<CoreGraphicsHintKeyboardTap>.fromOpaque(context).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { owner.receive(type, event: event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            return false
        }
        self.port = port
        self.source = source
        self.onEvent = onEvent
        self.onFailure = onFailure
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        guard CGEvent.tapIsEnabled(tap: port) else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        onEvent = nil
        onFailure = nil
        guard !ledger.isEmpty else {
            hardStop()
            return
        }
        drainTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hardStop() }
        }
        drainTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func hardStop() {
        drainTimer?.invalidate()
        drainTimer = nil
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        port = nil
        source = nil
        onEvent = nil
        onFailure = nil
        ledger = NavigationKeyLedger()
    }

    private func receive(_ type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            fail()
            return false
        default:
            break
        }
        guard event.getIntegerValueField(.eventSourceUserData) != HintEventMarker.userData else {
            return false
        }
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return onEvent?(.mouseDown) ?? false
        case .keyUp:
            let consumed = ledger.release(Self.keyCode(event))
            _ = onEvent?(.key(Self.raw(.keyUp, event)))
            if onEvent == nil, ledger.isEmpty { hardStop() }
            return consumed
        case .keyDown:
            return ledger.press(Self.keyCode(event),
                                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                active: onEvent != nil) {
                onEvent?(.key(Self.raw(.keyDown, event))) ?? false
            }
        case .flagsChanged:
            return onEvent?(.key(Self.raw(.flagsChanged, event))) ?? false
        default:
            return false
        }
    }

    private func fail() {
        let onFailure = onFailure
        hardStop()
        onFailure?()
    }

    private static func keyCode(_ event: CGEvent) -> UInt16 {
        UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    }

    private static func raw(_ kind: HintRawKeyEvent.Kind, _ event: CGEvent) -> HintRawKeyEvent {
        HintRawKeyEvent(
            kind: kind,
            keyCode: keyCode(event),
            flags: event.flags,
            characters: kind == .keyDown ? characters(event) : ""
        )
    }

    /// The event's own keyboard layout ignoring modifiers except Shift, which
    /// the classifier folds by lowercasing.
    private static func characters(_ event: CGEvent) -> String {
        NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
    }
}

final class NavigationKeyLedger {
    private var downs: [UInt16: Bool] = [:]
    var isEmpty: Bool { !downs.values.contains(true) }
    func press(_ code: UInt16, isRepeat: Bool = false, active: Bool = true, handle: () -> Bool) -> Bool {
        if let consumed = downs[code] { return consumed }
        if isRepeat { return active }
        downs[code] = true
        let consumed = handle()
        downs[code] = consumed
        return consumed
    }
    func release(_ code: UInt16) -> Bool { downs.removeValue(forKey: code) ?? false }
}
