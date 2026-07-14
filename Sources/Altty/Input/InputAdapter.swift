import AppKit
import Carbon
import Foundation

private let alttyHotKeySignature: OSType = 0x414C5459 // "ALTY"
private let allWindowsHotKeyID: UInt32 = 1
private let allWindowsReverseHotKeyID: UInt32 = 2

private let alttyCarbonHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    guard GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    ) == noErr,
          identifier.signature == alttyHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let adapter = Unmanaged<SystemInputAdapter>.fromOpaque(userData).takeUnretainedValue()
    let direction: SwitchDirection
    switch identifier.id {
    case allWindowsHotKeyID:
        direction = .forward
    case allWindowsReverseHotKeyID:
        direction = .backward
    default:
        return OSStatus(eventNotHandledErr)
    }
    MainActor.assumeIsolated { adapter.hotKeyPressed(direction: direction) }
    return noErr
}

enum ShortcutEvent: Equatable, Sendable {
    case allWindowsPressed(SwitchDirection)
    case holdModifiersReleased
    case cancel(SwitcherCancellationReason)
}

@MainActor
protocol InputAdapter: AnyObject {
    func install(onEvent: @escaping (ShortcutEvent) -> Void)
    func setShortcutsEnabled(_ enabled: Bool)
}

@MainActor
final class SystemInputAdapter: InputAdapter {
    private var onEvent: ((ShortcutEvent) -> Void)?
    private var hotKeys: [EventHotKeyRef] = []
    private var hotKeyHandler: EventHandlerRef?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var shortcutIsActive = false
    private(set) var shortcutsEnabled = false

    func install(onEvent: @escaping (ShortcutEvent) -> Void) {
        self.onEvent = onEvent
        installHotKeyHandlerIfNeeded()
    }

    func setShortcutsEnabled(_ enabled: Bool) {
        guard enabled != shortcutsEnabled else { return }
        if enabled {
            installHotKeyHandlerIfNeeded()
            guard registerHotKey(id: allWindowsHotKeyID, modifiers: UInt32(optionKey)),
                  registerHotKey(
                    id: allWindowsReverseHotKeyID,
                    modifiers: UInt32(optionKey | shiftKey)
                  ) else {
                unregisterHotKeys()
                return
            }
            installInteractionMonitors()
            shortcutsEnabled = true
        } else {
            if shortcutIsActive { onEvent?(.cancel(.shortcutInterrupted)) }
            shortcutIsActive = false
            unregisterHotKeys()
            removeInteractionMonitors()
            shortcutsEnabled = false
        }
    }

    private func registerHotKey(id: UInt32, modifiers: UInt32) -> Bool {
        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Tab),
            modifiers,
            EventHotKeyID(signature: alttyHotKeySignature, id: id),
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )
        guard status == noErr, let registeredHotKey else { return false }
        hotKeys.append(registeredHotKey)
        return true
    }

    private func unregisterHotKeys() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            alttyCarbonHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
    }

    private func installInteractionMonitors() {
        guard localFlagsMonitor == nil, globalFlagsMonitor == nil else { return }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            MainActor.assumeIsolated { self?.modifiersChanged(event.modifierFlags) }
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            Task { @MainActor [weak self] in self?.modifiersChanged(event.modifierFlags) }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            let consumed = MainActor.assumeIsolated {
                self?.consumeEscapeIfActive(keyCode: event.keyCode) ?? false
            }
            return consumed ? nil : event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor [weak self] in self?.cancel(.escape) }
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel(.outsideClick) }
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel(.lostInteractionContext) }
        }
    }

    private func removeInteractionMonitors() {
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let resignActiveObserver { NotificationCenter.default.removeObserver(resignActiveObserver) }
        localFlagsMonitor = nil
        globalFlagsMonitor = nil
        localKeyMonitor = nil
        globalKeyMonitor = nil
        globalClickMonitor = nil
        resignActiveObserver = nil
    }

    fileprivate func hotKeyPressed(direction: SwitchDirection) {
        guard shortcutsEnabled else { return }
        shortcutIsActive = true
        onEvent?(.allWindowsPressed(direction))
    }

    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        guard shortcutIsActive,
              !flags.intersection(.deviceIndependentFlagsMask).contains(.option) else { return }
        shortcutIsActive = false
        onEvent?(.holdModifiersReleased)
    }

    private func cancel(_ reason: SwitcherCancellationReason) {
        guard shortcutIsActive else { return }
        shortcutIsActive = false
        onEvent?(.cancel(reason))
    }

    func consumeEscapeIfActive(keyCode: UInt16) -> Bool {
        guard shortcutIsActive, keyCode == UInt16(kVK_Escape) else { return false }
        cancel(.escape)
        return true
    }

}
