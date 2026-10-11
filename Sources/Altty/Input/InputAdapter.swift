import AppKit
import Carbon
import Foundation

private let alttyHotKeySignature: OSType = 0x414C5459 // "ALTY"

struct RegisteredHotKey: Equatable, Sendable {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
}

@MainActor
protocol HotKeyRegistrar: AnyObject {
    func register(_ hotKey: RegisteredHotKey) -> Bool
    func unregister(id: UInt32) -> Bool
}

@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    private let signature: OSType
    private var references: [UInt32: EventHotKeyRef] = [:]

    init(signature: OSType = alttyHotKeySignature) { self.signature = signature }

    func register(_ hotKey: RegisteredHotKey) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            EventHotKeyID(signature: signature, id: hotKey.id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        references[hotKey.id] = reference
        return true
    }

    func unregister(id: UInt32) -> Bool {
        guard let reference = references[id] else { return true }
        guard UnregisterEventHotKey(reference) == noErr else { return false }
        references[id] = nil
        return true
    }
}

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
    let handled = MainActor.assumeIsolated { adapter.hotKeyPressed(id: identifier.id) }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}

enum ShortcutEvent: Equatable, Sendable {
    case switcherPressed(SwitcherMode, SwitchDirection)
    case navigate(SwitchDirection)
    case monitoringFailed
    case holdModifiersReleased
    case cancel(SwitcherCancellationReason)
}

enum ShortcutRegistrationResult: Equatable, Sendable {
    case applied
    case staged
    case failure(ShortcutConfigurationError)
}

@MainActor
protocol InputAdapter: AnyObject {
    var configuredShortcuts: ShortcutPair { get }
    func install(onEvent: @escaping (ShortcutEvent) -> Void)
    @discardableResult func setShortcutsEnabled(_ enabled: Bool) -> ShortcutRegistrationResult
    func replaceShortcuts(_ pair: ShortcutPair) -> ShortcutRegistrationResult
}

@MainActor
final class SystemInputAdapter: InputAdapter {
    private struct ActiveRegistration {
        let hotKey: RegisteredHotKey
        let mode: SwitcherMode
        let direction: SwitchDirection
        let binding: ShortcutBinding
    }

    private let registrar: any HotKeyRegistrar
    private let usesSystemMonitors: Bool
    private var onEvent: ((ShortcutEvent) -> Void)?
    private var activeRegistrations: [ActiveRegistration] = []
    private var nextHotKeyID: UInt32 = 1
    private var hotKeyHandler: EventHandlerRef?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private let gestureHistory: ShortcutGestureHistory?
    private var physicalMonitor: ShortcutPhysicalMonitor?
    private var physicalMonitorGeneration = UUID()
    private var activePhysicalPress: UInt64?
    private var shortcutIsActive = false
    private var previousModifiers: NSEvent.ModifierFlags = []
    private var activeHoldModifiers: ShortcutModifiers = []
    private(set) var configuredShortcuts: ShortcutPair
    private(set) var shortcutsEnabled = false

    init(
        registrar: any HotKeyRegistrar = CarbonHotKeyRegistrar(),
        shortcuts: ShortcutPair = .defaults,
        usesSystemMonitors: Bool = true,
        gestureHistory: ShortcutGestureHistory? = nil
    ) {
        self.registrar = registrar
        self.usesSystemMonitors = usesSystemMonitors
        self.gestureHistory = gestureHistory ?? (usesSystemMonitors ? ShortcutGestureHistory() : nil)
        self.configuredShortcuts = shortcuts.validationError == nil ? shortcuts : .defaults
    }

    func install(onEvent: @escaping (ShortcutEvent) -> Void) {
        self.onEvent = onEvent
        if usesSystemMonitors { _ = installHotKeyHandlerIfNeeded() }
    }

    @discardableResult
    func setShortcutsEnabled(_ enabled: Bool) -> ShortcutRegistrationResult {
        guard enabled != shortcutsEnabled
                || (!enabled && !activeRegistrations.isEmpty) else { return .applied }
        if enabled {
            guard !usesSystemMonitors || installHotKeyHandlerIfNeeded() else {
                return .failure(.inputMonitoringUnavailable)
            }
            let result = registerPairAtomically(configuredShortcuts, replacing: nil)
            guard result == .applied else {
                return unregisterHotKeys()
                    ? result
                    : .failure(.inputMonitoringUnavailable)
            }
            guard !usesSystemMonitors || installInteractionMonitors() else {
                _ = unregisterHotKeys()
                removeInteractionMonitors()
                return .failure(.inputMonitoringUnavailable)
            }
            shortcutsEnabled = true
        } else {
            if shortcutIsActive { onEvent?(.cancel(.shortcutInterrupted)) }
            shortcutIsActive = false
            activeHoldModifiers = []
            let unregistered = unregisterHotKeys()
            removeInteractionMonitors()
            shortcutsEnabled = false
            if !unregistered { return .failure(.inputMonitoringUnavailable) }
        }
        return .applied
    }

    func replaceShortcuts(_ pair: ShortcutPair) -> ShortcutRegistrationResult {
        if let error = pair.validationError { return .failure(error) }
        guard pair != configuredShortcuts else { return .applied }
        guard shortcutsEnabled else {
            configuredShortcuts = pair
            return .staged
        }
        return registerPairAtomically(pair, replacing: configuredShortcuts)
    }

    private func unregisterHotKeys() -> Bool {
        activeRegistrations.removeAll { registration in
            registrar.unregister(id: registration.hotKey.id)
        }
        return activeRegistrations.isEmpty
    }

    private func registerPairAtomically(
        _ pair: ShortcutPair,
        replacing previousPair: ShortcutPair?
    ) -> ShortcutRegistrationResult {
        if let error = pair.validationError { return .failure(error) }
        let changedModes = [SwitcherMode.allWindows, .currentApp].filter { mode in
            previousPair?.binding(for: mode) != pair.binding(for: mode)
        }
        var proposedRegistrations: [ActiveRegistration] = []

        for mode in changedModes {
            let binding = pair.binding(for: mode)
            guard let key = binding.key else { return .failure(.missingMainKey(mode)) }
            for direction in [SwitchDirection.forward, .backward] {
                let id = nextHotKeyID
                nextHotKeyID &+= 1
                let modifiers = direction == .forward
                    ? binding.modifiers.carbonValue
                    : binding.modifiers.union(.shift).carbonValue
                let hotKey = RegisteredHotKey(
                    id: id,
                    keyCode: key.keyCode,
                    modifiers: modifiers
                )
                guard registrar.register(hotKey) else {
                    let proposedStillRegistered = proposedRegistrations.filter {
                        !registrar.unregister(id: $0.hotKey.id)
                    }
                    guard proposedStillRegistered.isEmpty else {
                        activeRegistrations.append(contentsOf: proposedStillRegistered)
                        shortcutsEnabled = false
                        return .failure(.inputMonitoringUnavailable)
                    }
                    return .failure(.unavailableShortcut(mode))
                }
                proposedRegistrations.append(ActiveRegistration(
                    hotKey: hotKey,
                    mode: mode,
                    direction: direction,
                    binding: binding
                ))
            }
        }

        let retiredRegistrations = activeRegistrations.filter { registration in
            changedModes.contains(registration.mode)
        }
        var retired: [ActiveRegistration] = []
        for registration in retiredRegistrations {
            guard registrar.unregister(id: registration.hotKey.id) else {
                let proposedStillRegistered = proposedRegistrations.filter {
                    !registrar.unregister(id: $0.hotKey.id)
                }
                var failedRestorations: Set<UInt32> = []
                for removedRegistration in retired {
                    if !registrar.register(removedRegistration.hotKey) {
                        failedRestorations.insert(removedRegistration.hotKey.id)
                    }
                }
                let removedIDs = Set(retired.map(\.hotKey.id))
                activeRegistrations.removeAll {
                    removedIDs.contains($0.hotKey.id)
                        && failedRestorations.contains($0.hotKey.id)
                }
                activeRegistrations.append(contentsOf: proposedStillRegistered)
                if proposedStillRegistered.isEmpty && failedRestorations.isEmpty {
                    return .failure(.shortcutReplacementFailed)
                }
                shortcutsEnabled = false
                return .failure(.inputMonitoringUnavailable)
            }
            retired.append(registration)
        }
        activeRegistrations.removeAll { registration in
            changedModes.contains(registration.mode)
        }
        activeRegistrations.append(contentsOf: proposedRegistrations)
        configuredShortcuts = pair
        gestureHistory?.configure(activeRegistrations.map(\.hotKey))
        return .applied
    }

    private func installHotKeyHandlerIfNeeded() -> Bool {
        guard hotKeyHandler == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            alttyCarbonHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
        return status == noErr && hotKeyHandler != nil
    }

    private func installInteractionMonitors() -> Bool {
        guard localFlagsMonitor == nil, globalFlagsMonitor == nil else { return true }
        if let gestureHistory {
            let generation = UUID()
            physicalMonitorGeneration = generation
            let monitor = ShortcutPhysicalMonitor(history: gestureHistory, onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.physicalMonitorGeneration == generation else { return }
                    self.confirmPhysicalRelease()
                }
            }, onFailure: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.physicalMonitorGeneration == generation else { return }
                    _ = self.setShortcutsEnabled(false)
                    self.onEvent?(.monitoringFailed)
                }
            })
            guard monitor.start() else { return false }
            physicalMonitor = monitor
        }
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
        return localFlagsMonitor != nil
            && globalFlagsMonitor != nil
            && localKeyMonitor != nil
            && globalKeyMonitor != nil
            && globalClickMonitor != nil
            && resignActiveObserver != nil
    }

    private func removeInteractionMonitors() {
        physicalMonitorGeneration = UUID()
        physicalMonitor?.stop()
        physicalMonitor = nil
        activePhysicalPress = nil
        gestureHistory?.reset()
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

    @discardableResult
    func hotKeyPressed(id: UInt32) -> Bool {
        ShortcutDiagnostics.record("carbon_press registration=\(id) enabled=\(shortcutsEnabled)")
        guard shortcutsEnabled,
              let registration = activeRegistrations.first(where: {
                  $0.hotKey.id == id
              }) else { return false }
        // Drain the previous press before replacing its identity. A Carbon callback
        // can overtake the main-thread delivery of physical Shift changes.
        confirmPhysicalRelease()
        if let gestureHistory {
            guard let sequence = gestureHistory.claim(registration: id) else {
                ShortcutDiagnostics.record("unmatched_press registration=\(id)")
                return false
            }
            activePhysicalPress = sequence
        }
        shortcutIsActive = true
        previousModifiers = registration.binding.modifiers.eventFlags
        activeHoldModifiers = registration.binding.modifiers.intersection(.required)
        onEvent?(.switcherPressed(registration.mode, registration.direction))
        confirmPhysicalRelease()
        return true
    }

    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        if gestureHistory != nil { confirmPhysicalRelease(); return }
        let shiftPressed = flags.contains(.shift) && !previousModifiers.contains(.shift)
        previousModifiers = flags
        if shortcutIsActive, shiftPressed,
           !flags.intersection(activeHoldModifiers.eventFlags).isEmpty {
            onEvent?(.navigate(.backward))
        }
        guard shortcutIsActive,
              flags.intersection(.deviceIndependentFlagsMask)
                .intersection(activeHoldModifiers.eventFlags).isEmpty else { return }
        shortcutIsActive = false
        activeHoldModifiers = []
        onEvent?(.holdModifiersReleased)
    }

    private func confirmPhysicalRelease() {
        guard shortcutIsActive, let activePhysicalPress, let gestureHistory else { return }
        for _ in 0..<gestureHistory.takeReverseSteps(after: activePhysicalPress) {
            onEvent?(.navigate(.backward))
        }
        guard gestureHistory.canConfirm(activePhysicalPress) else { return }
        shortcutIsActive = false
        self.activePhysicalPress = nil
        activeHoldModifiers = []
        onEvent?(.holdModifiersReleased)
    }

    private func cancel(_ reason: SwitcherCancellationReason) {
        guard shortcutIsActive else { return }
        shortcutIsActive = false
        activePhysicalPress = nil
        activeHoldModifiers = []
        onEvent?(.cancel(reason))
    }

    func consumeEscapeIfActive(keyCode: UInt16) -> Bool {
        guard shortcutIsActive, keyCode == UInt16(kVK_Escape) else { return false }
        cancel(.escape)
        return true
    }

}
