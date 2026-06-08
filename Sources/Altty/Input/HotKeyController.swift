import AppKit
import Carbon.HIToolbox

protocol HotKeyControllerDelegate: AnyObject {
    func hotKeyControllerDidTriggerNextWindow(_ controller: HotKeyController)
    func hotKeyControllerDidReleaseHoldModifier(_ controller: HotKeyController)
}

final class HotKeyController {
    weak var delegate: HotKeyControllerDelegate?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let signature = OSType(UInt32(0x414c5459))
    private let hotKeyId = UInt32(1)
    private var isSwitcherHoldActive = false

    func start() {
        registerOptionTab()
        installEventTap()
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        eventTap = nil
        runLoopSource = nil
    }

    private func registerOptionTab() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
        ]
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, eventTypes.count, &eventTypes, selfPointer, &eventHandlerRef)
        let hotKey = EventHotKeyID(signature: signature, id: hotKeyId)
        RegisterEventHotKey(UInt32(kVK_Tab), UInt32(optionKey), hotKey, GetEventDispatcherTarget(), UInt32(kEventHotKeyNoOptions), &hotKeyRef)
    }

    private func installEventTap() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapHandler,
            userInfo: selfPointer
        )
        guard let eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    fileprivate func handleHotKeyPressed() {
        isSwitcherHoldActive = true
        delegate?.hotKeyControllerDidTriggerNextWindow(self)
    }

    fileprivate func handleFlagsChanged(_ flags: CGEventFlags) {
        guard isSwitcherHoldActive else { return }
        if !flags.contains(.maskAlternate) {
            isSwitcherHoldActive = false
            delegate?.hotKeyControllerDidReleaseHoldModifier(self)
        }
    }
}

private let hotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }
    var hotKeyId = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyId
    )
    let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
    if hotKeyId.id == 1 {
        DispatchQueue.main.async {
            controller.handleHotKeyPressed()
        }
    }
    return noErr
}

private let eventTapHandler: CGEventTapCallBack = { _, type, event, userData in
    guard let userData else { return Unmanaged.passUnretained(event) }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }
    if type == .flagsChanged {
        let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async {
            controller.handleFlagsChanged(event.flags)
        }
    }
    return Unmanaged.passUnretained(event)
}
