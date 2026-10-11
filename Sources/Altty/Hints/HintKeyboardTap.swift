import AppKit
import CoreGraphics

enum HintTapEvent: Equatable, Sendable {
    case key(HintRawKeyEvent)
    case mouseDown
}

@MainActor
protocol HintKeyboardTap: AnyObject {
    /// `onEvent` returns whether to swallow the event; `onFailure` reports a tap
    /// the system disabled and could not be re-enabled.
    func start(
        onEvent: @escaping @MainActor (HintTapEvent) -> Bool,
        onFailure: @escaping @MainActor () -> Void
    ) -> Bool
    func stop()
    /// The modifiers held right now, so a session knows what was already down.
    var currentFlags: CGEventFlags { get }
}

/// An active session tap on the main run loop. The key-up of every swallowed
/// key-down is swallowed too; events Altty posted itself pass untouched.
@MainActor
final class CoreGraphicsHintKeyboardTap: HintKeyboardTap {
    private static let keyEvents: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    private static let mouseEvents: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var onEvent: (@MainActor (HintTapEvent) -> Bool)?
    private var onFailure: (@MainActor () -> Void)?
    private var swallowedKeyCodes: Set<UInt16> = []

    var currentFlags: CGEventFlags { CGEventSource.flagsState(.combinedSessionState) }

    func start(
        onEvent: @escaping @MainActor (HintTapEvent) -> Bool,
        onFailure: @escaping @MainActor () -> Void
    ) -> Bool {
        stop()
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
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        port = nil
        source = nil
        onEvent = nil
        onFailure = nil
        swallowedKeyCodes.removeAll()
    }

    private func receive(_ type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout:
            if let port, CFMachPortIsValid(port) {
                CGEvent.tapEnable(tap: port, enable: true)
                if CGEvent.tapIsEnabled(tap: port) { return false }
            }
            fail()
            return false
        case .tapDisabledByUserInput:
            fail()
            return false
        default:
            break
        }
        guard let onEvent, event.getIntegerValueField(.eventSourceUserData) != HintEventMarker.userData else {
            return false
        }
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return onEvent(.mouseDown)
        case .keyUp:
            let keyCode = Self.keyCode(event)
            guard swallowedKeyCodes.remove(keyCode) == nil else { return true }
            return onEvent(.key(Self.raw(.keyUp, event)))
        case .keyDown:
            let swallow = onEvent(.key(Self.raw(.keyDown, event)))
            if swallow { swallowedKeyCodes.insert(Self.keyCode(event)) }
            return swallow
        case .flagsChanged:
            return onEvent(.key(Self.raw(.flagsChanged, event)))
        default:
            return false
        }
    }

    private func fail() {
        let onFailure = onFailure
        stop()
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
