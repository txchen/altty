import Carbon.HIToolbox
import CoreGraphics

struct HintRawKeyEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    let kind: Kind
    let keyCode: UInt16
    let flags: CGEventFlags
    /// The layout's characters for the key with every modifier stripped.
    let characters: String
}

/// Turns raw tap events into Hint keys. A Control tap is ⌃ going down and
/// back up with no other key or modifier in between; `initialFlags` keeps the
/// Hint Shortcut's own ⌃, released after the session starts, from counting.
struct HintKeyClassifier: Sendable {
    private static let modifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
    ]

    var shortcut: ShortcutBinding?
    private var modifiers: CGEventFlags
    private var controlTapArmed = false

    init(shortcut: ShortcutBinding?, initialFlags: CGEventFlags) {
        self.shortcut = shortcut
        modifiers = initialFlags.intersection(Self.modifierMask)
    }

    mutating func classify(_ event: HintRawKeyEvent) -> HintKey? {
        switch event.kind {
        case .keyUp:
            return nil
        case .flagsChanged:
            return flagsChanged(event.flags.intersection(Self.modifierMask))
        case .keyDown:
            controlTapArmed = false
            return keyDown(event)
        }
    }

    private mutating func flagsChanged(_ current: CGEventFlags) -> HintKey? {
        defer { modifiers = current }
        if current == .maskControl {
            if !modifiers.contains(.maskControl) { controlTapArmed = true }
            return nil
        }
        let tapped = current.isEmpty && controlTapArmed
        controlTapArmed = false
        return tapped ? .controlTap : nil
    }

    private func keyDown(_ event: HintRawKeyEvent) -> HintKey {
        let modifiers = HintClickModifiers(eventFlags: event.flags)
        if let shortcut, let key = shortcut.key, key.keyCode == UInt32(event.keyCode),
           shortcut.modifiers == ShortcutModifiers(modifiers) {
            return .hintShortcut
        }
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter(modifiers)
        default: break
        }
        if !modifiers.isDisjoint(with: [.command, .control, .option]) { return .passThroughChord }
        switch Int(event.keyCode) {
        case kVK_Escape: return .escape
        case kVK_Delete: return .backspace
        default: break
        }
        let characters = event.characters.lowercased()
        guard characters.count == 1, let letter = characters.first, letter.isLetter else { return .other }
        return .letter(letter)
    }
}

private extension ShortcutModifiers {
    init(_ modifiers: HintClickModifiers) {
        var value: ShortcutModifiers = []
        if modifiers.contains(.command) { value.insert(.command) }
        if modifiers.contains(.shift) { value.insert(.shift) }
        if modifiers.contains(.option) { value.insert(.option) }
        if modifiers.contains(.control) { value.insert(.control) }
        self = value
    }
}
