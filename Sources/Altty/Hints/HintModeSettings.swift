import Foundation

struct HintModeSettings: Codable, Equatable, Sendable {
    static let disabled = HintModeSettings(enabled: false, shortcut: nil)

    let enabled: Bool
    let shortcut: ShortcutBinding?

    func validationError(against pair: ShortcutPair) -> HintShortcutError? {
        guard let shortcut else { return nil }
        guard shortcut.key != nil else { return .missingMainKey }
        if shortcut.modifiers.intersection(.required).isEmpty { return .missingRequiredModifier }
        let switcherChords = [pair.allWindows, pair.currentApp].flatMap { binding in
            [binding, ShortcutBinding(key: binding.key, modifiers: binding.modifiers.union(.shift))]
        }
        if switcherChords.contains(where: { $0.key?.keyCode == shortcut.key?.keyCode && $0.modifiers == shortcut.modifiers }) {
            return .conflictsWithSwitcher
        }
        return nil
    }
}

enum HintShortcutError: Error, Equatable, Sendable {
    case missingMainKey
    case missingRequiredModifier
    case conflictsWithSwitcher
    case unavailable

    var message: String {
        switch self {
        case .missingMainKey: "Choose a main key for the Hint shortcut."
        case .missingRequiredModifier: "The Hint shortcut requires Option, Control, or Command."
        case .conflictsWithSwitcher: "This shortcut is already used by a window switcher."
        case .unavailable: "The Hint shortcut is used by another application. Choose a different shortcut."
        }
    }
}
