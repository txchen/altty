import Carbon
import Foundation

private let hintHotKeySignature: OSType = 0x414C5448 // "ALTH"
private let hintHotKeyID: UInt32 = 1

private let hintCarbonHotKeyHandler: EventHandlerUPP = { _, event, userData in
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
          identifier.signature == Unmanaged<CarbonHintShortcutAdapter>.fromOpaque(userData).takeUnretainedValue().signature else {
        return OSStatus(eventNotHandledErr)
    }
    let adapter = Unmanaged<CarbonHintShortcutAdapter>.fromOpaque(userData).takeUnretainedValue()
    let handled = MainActor.assumeIsolated { adapter.hotKeyPressed(id: identifier.id) }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}

/// Registers the Hint Shortcut under its own Carbon signature, so the switcher
/// pair transaction and its handler never see it.
@MainActor
final class CarbonHintShortcutAdapter: HintShortcutAdapter {
    let signature: OSType
    private let registrar: any HotKeyRegistrar
    private let installsEventHandler: Bool
    private var onPress: (@MainActor () -> Void)?
    private var eventHandler: EventHandlerRef?
    private(set) var registeredShortcut: ShortcutBinding?

    init(
        registrar: (any HotKeyRegistrar)? = nil,
        signature: OSType = hintHotKeySignature,
        installsEventHandler: Bool = true
    ) {
        self.signature = signature
        self.registrar = registrar ?? CarbonHotKeyRegistrar(signature: signature)
        self.installsEventHandler = installsEventHandler
    }

    func install(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
    }

    func setShortcut(_ binding: ShortcutBinding?) -> Bool {
        guard binding != registeredShortcut else { return true }
        if registeredShortcut != nil {
            guard registrar.unregister(id: hintHotKeyID) else { return false }
            registeredShortcut = nil
        }
        guard let binding else { return true }
        guard let key = binding.key,
              !installsEventHandler || installEventHandlerIfNeeded(),
              registrar.register(RegisteredHotKey(
                  id: hintHotKeyID,
                  keyCode: key.keyCode,
                  modifiers: binding.modifiers.carbonValue
              )) else { return false }
        registeredShortcut = binding
        return true
    }

    @discardableResult
    func hotKeyPressed(id: UInt32) -> Bool {
        guard id == hintHotKeyID, registeredShortcut != nil, let onPress else { return false }
        onPress()
        return true
    }

    private func installEventHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hintCarbonHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        return status == noErr && eventHandler != nil
    }
}
