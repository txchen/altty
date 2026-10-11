import CoreGraphics
import Testing
@testable import Altty

struct HintLabelsTests {
    private func isPrefixFree(_ labels: [String]) -> Bool {
        let all = Set(labels)
        guard all.count == labels.count else { return false }
        return labels.allSatisfy { label in
            (1..<label.count).allSatisfy { !all.contains(String(label.prefix($0))) }
        }
    }

    @Test func smallCountsUseSingleHomeRowLetters() {
        #expect(HintLabels.make(count: 0).isEmpty)
        #expect(HintLabels.make(count: 1) == ["a"])
        #expect(HintLabels.make(count: 9) == ["a", "s", "d", "f", "g", "h", "j", "k", "l"])
    }

    @Test func oneMoreThanTheAlphabetExpandsOnlyTheLastPrefix() {
        #expect(HintLabels.make(count: 10) == ["a", "s", "d", "f", "g", "h", "j", "k", "la", "ls"])
    }

    @Test func eightyOneTargetsUseEveryTwoLetterLabel() {
        let labels = HintLabels.make(count: 81)
        #expect(labels.count == 81)
        #expect(labels.allSatisfy { $0.count == 2 })
        #expect(labels.first == "aa")
        #expect(labels[1] == "as")
        #expect(labels.last == "ll")
    }

    @Test func eightyTwoTargetsExpandTheLastTwoLetterPrefix() {
        let labels = HintLabels.make(count: 82)
        #expect(labels.count == 82)
        #expect(labels.prefix(80).allSatisfy { $0.count == 2 })
        #expect(labels.suffix(2) == ["lla", "lls"])
    }

    @Test func capacityIsTheAlphabetCubed() {
        let labels = HintLabels.make(count: 729)
        #expect(HintLabels.capacity() == 729)
        #expect(labels.count == 729)
        #expect(labels.allSatisfy { $0.count == 3 })
        #expect(HintLabels.make(count: 2000).count == 729)
    }

    @Test func everyCountIsPrefixFreeAndUsesOnlyTheAlphabet() {
        let alphabet = Set(HintLabels.alphabet)
        for count in 1...729 {
            let labels = HintLabels.make(count: count)
            #expect(labels.count == count)
            #expect(isPrefixFree(labels), "count \(count)")
            #expect(labels.allSatisfy { $0.allSatisfy(alphabet.contains) && $0.count <= 3 })
        }
    }

    @Test func customAlphabetIsHonoured() {
        #expect(HintLabels.make(count: 3, alphabet: ["x", "y"]) == ["x", "yx", "yy"])
        #expect(HintLabels.make(count: 2, alphabet: ["x"]).isEmpty)
    }

    @Test func readingOrderIsTopToBottomThenLeftToRight() {
        let frames = [
            CGRect(x: 200, y: 10.3, width: 5, height: 5),
            CGRect(x: 10, y: 50, width: 5, height: 5),
            CGRect(x: 100, y: 10, width: 5, height: 5),
        ]
        #expect(frames.sorted(by: HintLabels.readingOrder).map(\.minX) == [100, 200, 10])
    }
}

struct HintDefaultActionTests {
    @Test func roleTableFollowsShortcatsRule() {
        #expect(HintDefaultAction(role: "AXButton") == .press)
        #expect(HintDefaultAction(role: "AXMenuItem") == .press)
        #expect(HintDefaultAction(role: "AXMenuBarItem") == .press)
        #expect(HintDefaultAction(role: "AXWindow") == .raise)
        for role in ["AXLink", "AXCheckBox", "AXCell", "AXRow", "AXTextField", "AXPopUpButton", "AXUnknown"] {
            #expect(HintDefaultAction(role: role) == .click)
        }
    }

    @Test func clickModifiersRoundTripEventFlags() {
        let all: HintClickModifiers = [.command, .shift, .option, .control]
        #expect(HintClickModifiers(eventFlags: all.eventFlags) == all)
        #expect(HintClickModifiers(eventFlags: [.maskAlphaShift, .maskNumericPad]).isEmpty)
    }
}
