import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import Altty

struct HintKeyClassifierTests {
    private static let shortcut = ShortcutBinding(
        key: ShortcutKey(keyCode: UInt32(kVK_ANSI_F), displayName: "F"),
        modifiers: [.control, .option, .shift, .command]
    )

    private func classifier(initialFlags: CGEventFlags = []) -> HintKeyClassifier {
        HintKeyClassifier(shortcut: Self.shortcut, initialFlags: initialFlags)
    }

    private func down(_ keyCode: Int, _ characters: String = "", flags: CGEventFlags = []) -> HintRawKeyEvent {
        HintRawKeyEvent(kind: .keyDown, keyCode: UInt16(keyCode), flags: flags, characters: characters)
    }

    private func flags(_ flags: CGEventFlags) -> HintRawKeyEvent {
        HintRawKeyEvent(kind: .flagsChanged, keyCode: UInt16(kVK_Control), flags: flags, characters: "")
    }

    @Test func lettersAreLowercasedLayoutCharacters() {
        var keys = classifier()
        #expect(keys.classify(down(kVK_ANSI_A, "a")) == .letter("a"))
        #expect(keys.classify(down(kVK_ANSI_A, "A", flags: .maskShift)) == .letter("a"))
        #expect(keys.classify(down(kVK_ANSI_Q, "й")) == .letter("й"))
        #expect(keys.classify(down(kVK_ANSI_1, "1")) == .other)
        #expect(keys.classify(down(kVK_Space, " ")) == .other)
        #expect(keys.classify(down(kVK_LeftArrow, "", flags: .maskSecondaryFn)) == .other)
    }

    @Test func keyUpsAreNotKeys() {
        var keys = classifier()
        #expect(keys.classify(HintRawKeyEvent(kind: .keyUp, keyCode: UInt16(kVK_ANSI_A), flags: [], characters: "a")) == nil)
    }

    @Test func returnAndKeypadEnterCarryTheirModifiers() {
        var keys = classifier()
        #expect(keys.classify(down(kVK_Return)) == .enter([]))
        #expect(keys.classify(down(kVK_ANSI_KeypadEnter)) == .enter([]))
        #expect(keys.classify(down(kVK_Return, flags: [.maskCommand, .maskShift])) == .enter([.command, .shift]))
        #expect(keys.classify(down(kVK_Return, flags: .maskControl)) == .enter(.control))
        #expect(keys.classify(down(kVK_Return, flags: [.maskAlternate, .maskAlphaShift])) == .enter(.option))
    }

    @Test func escapeAndDeleteAreRecognised() {
        var keys = classifier()
        #expect(keys.classify(down(kVK_Escape)) == .escape)
        #expect(keys.classify(down(kVK_Delete)) == .backspace)
        #expect(keys.classify(down(kVK_Delete, flags: .maskShift)) == .backspace)
    }

    @Test func commandControlAndOptionChordsPassThrough() {
        var keys = classifier()
        #expect(keys.classify(down(kVK_ANSI_A, "a", flags: .maskCommand)) == .passThroughChord)
        #expect(keys.classify(down(kVK_ANSI_A, "a", flags: .maskControl)) == .passThroughChord)
        #expect(keys.classify(down(kVK_ANSI_A, "a", flags: .maskAlternate)) == .passThroughChord)
        #expect(keys.classify(down(kVK_Delete, flags: .maskCommand)) == .passThroughChord)
        #expect(keys.classify(down(kVK_Escape, flags: .maskCommand)) == .passThroughChord)
    }

    @Test func theHintShortcutNeedsItsExactModifiers() {
        var keys = classifier()
        let all: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        #expect(keys.classify(down(kVK_ANSI_F, "f", flags: all)) == .hintShortcut)
        #expect(keys.classify(down(kVK_ANSI_F, "f", flags: [.maskControl, .maskAlternate, .maskCommand])) == .passThroughChord)
        keys.shortcut = nil
        #expect(keys.classify(down(kVK_ANSI_F, "f", flags: all)) == .passThroughChord)
    }

    @Test func controlDownThenUpIsATap() {
        var keys = classifier()
        #expect(keys.classify(flags(.maskControl)) == nil)
        #expect(keys.classify(flags([])) == .controlTap)
        #expect(keys.classify(flags([])) == nil)
    }

    @Test func aKeyBetweenControlDownAndUpCancelsTheTap() {
        var keys = classifier()
        _ = keys.classify(flags(.maskControl))
        _ = keys.classify(down(kVK_ANSI_A, "a", flags: .maskControl))
        #expect(keys.classify(flags([])) == nil)
    }

    @Test func anotherModifierBetweenControlDownAndUpCancelsTheTap() {
        var keys = classifier()
        _ = keys.classify(flags(.maskControl))
        _ = keys.classify(flags([.maskControl, .maskShift]))
        _ = keys.classify(flags(.maskControl))
        #expect(keys.classify(flags([])) == nil)
    }

    @Test func controlAddedToAnotherHeldModifierIsNotATap() {
        var keys = classifier()
        _ = keys.classify(flags(.maskShift))
        _ = keys.classify(flags([.maskShift, .maskControl]))
        _ = keys.classify(flags(.maskShift))
        #expect(keys.classify(flags([])) == nil)
    }

    @Test func theShortcutsOwnControlReleaseIsNotATap() {
        var keys = classifier(initialFlags: [.maskControl, .maskAlternate, .maskShift, .maskCommand])
        _ = keys.classify(flags([.maskControl, .maskAlternate]))
        _ = keys.classify(flags(.maskControl))
        #expect(keys.classify(flags([])) == nil)
        _ = keys.classify(flags(.maskControl))
        #expect(keys.classify(flags([])) == .controlTap)
    }

    @Test func capsLockDoesNotDisturbATap() {
        var keys = classifier(initialFlags: .maskAlphaShift)
        _ = keys.classify(flags([.maskControl, .maskAlphaShift]))
        #expect(keys.classify(flags(.maskAlphaShift)) == .controlTap)
    }
}
