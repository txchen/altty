// Adapted from Scroll Reverser, Copyright 2011 Nicholas Moore, Apache-2.0.
// Changes: Swift adapter, atomic tap lifecycle, one mouse-only setting and
// injectable system seams. See Resources/ThirdParty/ScrollReverser/NOTICE.
import AppKit
import CoreGraphics
import Foundation

enum MouseScrollStatus: Equatable, Sendable {
    case disabled
    case active
    case unavailable
    case inputMonitoringRequired
}

// Apply only after classification. Read every representation before writing:
// setting a line delta also changes the point and fixed-point representations.
enum MouseWheelReversal {
    static func apply(to event: CGEvent) {
        guard event.type == .scrollWheel else { return }
        let lineFields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
        ]
        let pointFields: [CGEventField] = [
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
        ]
        let fixedFields: [CGEventField] = [
            .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
        ]
        let lines = lineFields.map { event.getIntegerValueField($0) }
        let points = pointFields.map { event.getIntegerValueField($0) }
        let fixed = fixedFields.map { event.getDoubleValueField($0) }
        guard !(lines + points).contains(Int64.min) else { return }
        for (field, value) in zip(lineFields, lines) {
            event.setIntegerValueField(field, value: -value)
        }
        for (field, value) in zip(fixedFields, fixed) {
            event.setDoubleValueField(field, value: -value)
        }
        for (field, value) in zip(pointFields, points) {
            event.setIntegerValueField(field, value: -value)
        }
    }
}

@MainActor
protocol MouseScrollAdapter: AnyObject {
    func installStatusHandler(_ handler: @escaping (MouseScrollStatus) -> Void)
    @discardableResult func setEnabled(_ enabled: Bool) -> MouseScrollStatus
    func requestInputMonitoringPermission()
}

// The explicit system seam lets tests drive the real callback without capturing
// or posting any mouse input in the user's session.
@MainActor
protocol MouseScrollEventTap: AnyObject {
    func start(_ handler: @escaping @MainActor (CGEventType, CGEvent) -> Void) -> Bool
    func reenable() -> Bool
    func stop()
}

@MainActor
final class SystemMouseScrollAdapter: MouseScrollAdapter {
    private let tap: any MouseScrollEventTap
    private let hid: any MouseScrollHIDAccess
    private let canListen: () -> Bool
    private let now: () -> UInt64
    private var classifier = ScrollInputClassifier()
    private var enabled = false
    private var onStatus: ((MouseScrollStatus) -> Void)?

    init(
        tap: any MouseScrollEventTap = CoreGraphicsMouseScrollEventTap(),
        hid: any MouseScrollHIDAccess = SystemMouseScrollHIDAccess(),
        canListen: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.tap = tap
        self.hid = hid
        self.canListen = canListen
        self.now = now
    }

    func installStatusHandler(_ handler: @escaping (MouseScrollStatus) -> Void) {
        onStatus = handler
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> MouseScrollStatus {
        guard enabled else {
            self.enabled = false
            classifier = ScrollInputClassifier()
            tap.stop()
            return .disabled
        }
        if self.enabled { return .active }
        guard canListen() else { return .inputMonitoringRequired }
        guard hid.isAvailable else { return .unavailable }
        classifier = ScrollInputClassifier()
        guard tap.start({ [weak self] type, event in self?.receive(type, event: event) }) else {
            tap.stop()
            return .unavailable
        }
        self.enabled = true
        return .active
    }

    func requestInputMonitoringPermission() {
        guard !canListen() else { return }
        _ = CGRequestListenEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func receive(_ type: CGEventType, event: CGEvent) {
        guard enabled else { return }
        if type.rawValue == NSEvent.EventType.gesture.rawValue {
            if let gesture = NSEvent(cgEvent: event) {
                classifier.observeTouches(gesture.touches(matching: .touching, in: nil).count, at: now())
            }
            return
        }
        switch type {
        case .tapDisabledByTimeout:
            if !tap.reenable() { fail() }
        case .tapDisabledByUserInput:
            fail()
        case .scrollWheel:
            let momentum = !(NSEvent(cgEvent: event)?.momentumPhase.isEmpty ?? true)
            let source = classifier.source(
                continuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                momentum: momentum,
                at: now()
            )
            if source == .mouse {
                let reverseHID = hid.prepareReversal(for: event)
                MouseWheelReversal.apply(to: event)
                reverseHID?()
            }
        default:
            break
        }
    }

    private func fail() {
        enabled = false
        tap.stop()
        onStatus?(.unavailable)
    }
}

@MainActor
private final class CoreGraphicsMouseScrollEventTap: MouseScrollEventTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesturePort: CFMachPort?
    private var gestureSource: CFRunLoopSource?
    private var handler: (@MainActor (CGEventType, CGEvent) -> Void)?

    func start(_ handler: @escaping @MainActor (CGEventType, CGEvent) -> Void) -> Bool {
        stop()
        self.handler = handler
        // Gesture observation must be passive: active gesture taps interfere
        // with system gestures and authorization dialogs (upstream finding).
        guard let gesturePort = createTap(mask: UInt64(NSEvent.EventType.gesture.rawValue), options: .listenOnly) else {
            stop()
            return false
        }
        self.gesturePort = gesturePort
        guard let gestureSource = CFMachPortCreateRunLoopSource(nil, gesturePort, 0) else {
            stop()
            return false
        }
        self.gestureSource = gestureSource
        guard let port = createTap(mask: UInt64(CGEventType.scrollWheel.rawValue), options: .defaultTap) else {
            stop()
            return false
        }
        self.port = port
        guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            stop()
            return false
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), gestureSource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return reenable()
    }

    private func createTap(mask: UInt64, options: CGEventTapOptions) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: options,
            eventsOfInterest: CGEventMask(1) << mask,
            callback: { _, type, event, context in
                if let context {
                    let owner = Unmanaged<CoreGraphicsMouseScrollEventTap>
                        .fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { owner.handler?(type, event) }
                }
                // Modify in place, never suppress or repost (which could reverse twice).
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func reenable() -> Bool {
        guard let port, let gesturePort,
              CFMachPortIsValid(port), CFMachPortIsValid(gesturePort) else { return false }
        CGEvent.tapEnable(tap: port, enable: true)
        CGEvent.tapEnable(tap: gesturePort, enable: true)
        return CGEvent.tapIsEnabled(tap: port) && CGEvent.tapIsEnabled(tap: gesturePort)
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        if let gesturePort { CGEvent.tapEnable(tap: gesturePort, enable: false) }
        if let gestureSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureSource, .commonModes) }
        if let gesturePort { CFMachPortInvalidate(gesturePort) }
        source = nil
        port = nil
        gestureSource = nil
        gesturePort = nil
        handler = nil
    }
}
