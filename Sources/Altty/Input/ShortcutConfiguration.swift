import AppKit
import Carbon
import Foundation

struct ShortcutKey: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let displayName: String
}

struct ShortcutModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    let rawValue: UInt8

    static let option = ShortcutModifiers(rawValue: 1 << 0)
    static let control = ShortcutModifiers(rawValue: 1 << 1)
    static let command = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    static let required: ShortcutModifiers = [.option, .control, .command]

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.command) { value.insert(.command) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        self = value
    }

    var carbonValue: UInt32 {
        var value: UInt32 = 0
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        return flags
    }
}

struct ShortcutBinding: Codable, Equatable, Sendable {
    let key: ShortcutKey?
    let modifiers: ShortcutModifiers

    var displayName: String {
        let modifierNames = [
            modifiers.contains(.control) ? "⌃" : "",
            modifiers.contains(.option) ? "⌥" : "",
            modifiers.contains(.shift) ? "⇧" : "",
            modifiers.contains(.command) ? "⌘" : "",
        ].joined()
        return modifierNames + (key?.displayName ?? "Record Shortcut")
    }
}

struct ShortcutPair: Codable, Equatable, Sendable {
    let allWindows: ShortcutBinding
    let currentApp: ShortcutBinding

    static let defaults = ShortcutPair(
        allWindows: ShortcutBinding(
            key: ShortcutKey(keyCode: UInt32(kVK_Tab), displayName: "Tab"),
            modifiers: [.option]
        ),
        currentApp: ShortcutBinding(
            key: ShortcutKey(keyCode: UInt32(kVK_ANSI_Grave), displayName: "`"),
            modifiers: [.option]
        )
    )

    var validationError: ShortcutConfigurationError? {
        for (mode, binding) in [
            (SwitcherMode.allWindows, allWindows),
            (SwitcherMode.currentApp, currentApp),
        ] {
            guard binding.key != nil else { return .missingMainKey(mode) }
            if binding.modifiers.contains(.shift) { return .shiftIsReserved(mode) }
            if binding.modifiers.intersection(.required).isEmpty {
                return .missingRequiredModifier(mode)
            }
        }
        if allWindows == currentApp { return .duplicateBindings }
        return nil
    }

    func binding(for mode: SwitcherMode) -> ShortcutBinding {
        switch mode {
        case .allWindows: allWindows
        case .currentApp: currentApp
        }
    }

    func replacing(_ mode: SwitcherMode, with binding: ShortcutBinding) -> ShortcutPair {
        switch mode {
        case .allWindows:
            ShortcutPair(allWindows: binding, currentApp: currentApp)
        case .currentApp:
            ShortcutPair(allWindows: allWindows, currentApp: binding)
        }
    }
}

enum ShortcutConfigurationError: Error, Equatable, Sendable {
    case missingMainKey(SwitcherMode)
    case missingRequiredModifier(SwitcherMode)
    case shiftIsReserved(SwitcherMode)
    case duplicateBindings
    case conflictsWithHintShortcut(SwitcherMode)
    case unavailableShortcut(SwitcherMode)
    case shortcutReplacementFailed
    case inputMonitoringUnavailable
    case couldNotSaveSettings

    var message: String {
        switch self {
        case let .missingMainKey(mode):
            "Choose a main key for \(mode.title)."
        case let .missingRequiredModifier(mode):
            "\(mode.title) requires Option, Control, or Command."
        case let .shiftIsReserved(mode):
            "Shift is reserved for reverse \(mode.title) navigation."
        case .duplicateBindings:
            "All-Windows and Current-App must use different shortcuts."
        case let .conflictsWithHintShortcut(mode):
            "\(mode.title) cannot use the Hint shortcut or its Shift variant."
        case let .unavailableShortcut(mode):
            "The \(mode.title) shortcut is unavailable. Your previous shortcuts are still active."
        case .shortcutReplacementFailed:
            "The shortcut pair could not be replaced. Your previous shortcuts are still active."
        case .inputMonitoringUnavailable:
            "Keyboard monitoring is unavailable. Altty shortcuts have been unregistered so the keys pass through."
        case .couldNotSaveSettings:
            "The shortcut is active for this launch, but Altty could not save it."
        }
    }
}

struct ShortcutSettingsState: Equatable, Sendable {
    var current: ShortcutPair
    var pending: ShortcutPair?
    var error: ShortcutConfigurationError?
    var recoveryWarning: String?

    var inlineMessage: String? {
        error?.message ?? recoveryWarning
    }
}

enum ShortcutRegistrationEvent: Equatable, Sendable {
    case applied(ShortcutPair)
    case failed(ShortcutPair, ShortcutConfigurationError)
    case recoveredWithDefaults(ShortcutConfigurationError)
}
