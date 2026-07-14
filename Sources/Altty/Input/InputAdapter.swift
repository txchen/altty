import AppKit
import Carbon
import Foundation

private let alttyHotKeySignature: OSType = 0x414C5459 // "ALTY"
private let allWindowsHotKeyID: UInt32 = 1

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
          identifier.signature == alttyHotKeySignature,
          identifier.id == allWindowsHotKeyID else {
        return OSStatus(eventNotHandledErr)
    }
    let adapter = Unmanaged<SystemInputAdapter>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { adapter.hotKeyPressed() }
    return noErr
}

enum ShortcutEvent: Equatable, Sendable {
    case allWindowsPressed
    case holdModifiersReleased
}

@MainActor
protocol InputAdapter: AnyObject {
    func install(onEvent: @escaping (ShortcutEvent) -> Void)
    func setShortcutsEnabled(_ enabled: Bool)
}

@MainActor
final class SystemInputAdapter: InputAdapter {
    private var onEvent: ((ShortcutEvent) -> Void)?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
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
            var registeredHotKey: EventHotKeyRef?
            let identifier = EventHotKeyID(
                signature: alttyHotKeySignature,
                id: allWindowsHotKeyID
            )
            let status = RegisterEventHotKey(
                UInt32(kVK_Tab),
                UInt32(optionKey),
                identifier,
                GetApplicationEventTarget(),
                0,
                &registeredHotKey
            )
            guard status == noErr, let registeredHotKey else { return }
            hotKey = registeredHotKey
            installModifierMonitors()
            shortcutsEnabled = true
        } else {
            shortcutIsActive = false
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            removeModifierMonitors()
            shortcutsEnabled = false
        }
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

    private func installModifierMonitors() {
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
    }

    private func removeModifierMonitors() {
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
        localFlagsMonitor = nil
        globalFlagsMonitor = nil
    }

    fileprivate func hotKeyPressed() {
        guard shortcutsEnabled else { return }
        shortcutIsActive = true
        onEvent?(.allWindowsPressed)
    }

    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        guard shortcutIsActive,
              !flags.intersection(.deviceIndependentFlagsMask).contains(.option) else { return }
        shortcutIsActive = false
        onEvent?(.holdModifiersReleased)
    }

}
