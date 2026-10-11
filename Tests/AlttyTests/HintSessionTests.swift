import Testing
@testable import Altty

struct HintSessionTests {
    private func session(_ actions: [HintDefaultAction]) -> HintSession {
        HintSession(defaultActions: actions)
    }

    private func clickSession(count: Int = 10) -> HintSession {
        session(Array(repeating: .click, count: count))
    }

    private func typing(_ text: String, into session: inout HintSession) -> [HintStep] {
        text.map { session.handle(.letter($0)) }
    }

    @Test func typingFiltersLabelsByPrefixAndDimsTheTypedPart() {
        var hints = clickSession()
        #expect(hints.badges.count == 10)
        #expect(hints.handle(.letter("l")) == .redrawn)
        #expect(hints.typed == "l")
        #expect(hints.badges == [
            HintBadge(target: 8, label: "la", typedCount: 1, isSelected: false),
            HintBadge(target: 9, label: "ls", typedCount: 1, isSelected: false),
        ])
    }

    @Test func aCompleteLabelSelectsAndResetsThePrefixSoAnotherLabelMovesTheSelection() {
        var hints = clickSession()
        _ = typing("ls", into: &hints)
        #expect(hints.selection == 9)
        #expect(hints.typed.isEmpty)
        #expect(hints.badges.count == 10)
        #expect(hints.badges.filter(\.isSelected).map(\.label) == ["ls"])
        #expect(hints.handle(.letter("d")) == .redrawn)
        #expect(hints.selection == 2)
    }

    @Test func theSelectedBadgeStaysVisibleWhileAnotherPrefixIsTyped() {
        var hints = clickSession()
        _ = hints.handle(.letter("a"))
        _ = hints.handle(.letter("l"))
        #expect(hints.badges.map(\.label) == ["a", "la", "ls"])
        #expect(hints.badges.first == HintBadge(target: 0, label: "a", typedCount: 0, isSelected: true))
    }

    @Test func aLetterMatchingNoLabelIsIgnored() {
        var hints = clickSession()
        #expect(hints.handle(.letter("z")) == .ignored)
        #expect(hints.handle(.letter("l")) == .redrawn)
        let before = hints
        #expect(hints.handle(.letter("l")) == .ignored)
        #expect(hints == before)
    }

    @Test func backspacePopsALetterThenClearsTheSelection() {
        var hints = clickSession()
        _ = hints.handle(.letter("a"))
        _ = hints.handle(.letter("l"))
        #expect(hints.handle(.backspace) == .redrawn)
        #expect(hints.typed.isEmpty)
        #expect(hints.selection == 0)
        #expect(hints.handle(.backspace) == .redrawn)
        #expect(hints.selection == nil)
        #expect(hints.handle(.backspace) == .ignored)
    }

    @Test func enterWithoutSelectionDoesNothing() {
        var hints = clickSession()
        #expect(hints.handle(.enter([])) == .ignored)
        #expect(hints.handle(.enter(.command)) == .ignored)
        #expect(hints.handle(.enter(.control)) == .ignored)
    }

    @Test func enterOnAClickTargetClicksThenASecondEnterDoubleClicks() {
        var hints = clickSession()
        _ = hints.handle(.letter("f"))
        #expect(hints.handle(.enter([])) == .performing(.defaultAction, on: 3, then: .awaitSecondClick))
        #expect(hints.phase == .awaitingSecondClick(target: 3))
        #expect(hints.badges.isEmpty)
        #expect(hints.handle(.enter([])) == .performing(.secondClickOfDouble, on: 3))
    }

    @Test func anyOtherKeyDuringTheDoubleClickWindowEndsAndPassesThrough() {
        for key in [HintKey.letter("a"), .escape, .enter(.command), .backspace, .controlTap, .hintShortcut, .other] {
            var hints = clickSession()
            _ = hints.handle(.letter("a"))
            _ = hints.handle(.enter([]))
            #expect(hints.handle(key) == .passedThroughAndEnded, "\(key)")
        }
    }

    @Test func theDoubleClickWindowExpiresOnlyWhileAwaiting() {
        var hints = clickSession()
        let idle = hints.doubleClickWindowExpired()
        _ = hints.handle(.letter("a"))
        _ = hints.handle(.enter([]))
        let awaiting = hints.doubleClickWindowExpired()
        let afterwards = hints.doubleClickWindowExpired()
        #expect(!idle)
        #expect(awaiting)
        #expect(!afterwards)
    }

    @Test func enterOnPressAndRaiseTargetsPerformsAndEnds() {
        var hints = session([.press, .raise])
        _ = hints.handle(.letter("a"))
        #expect(hints.handle(.enter([])) == .performing(.defaultAction, on: 0))
        var raised = session([.press, .raise])
        _ = raised.handle(.letter("s"))
        #expect(raised.handle(.enter([])) == .performing(.defaultAction, on: 1))
    }

    @Test func controlEnterRightClicksEvenWithOtherModifiers() {
        for modifiers: HintClickModifiers in [.control, [.control, .command], [.control, .shift, .option]] {
            var hints = session([.press])
            _ = hints.handle(.letter("a"))
            #expect(hints.handle(.enter(modifiers)) == .performing(.rightClick, on: 0))
        }
    }

    @Test func otherModifierEnterClicksWithThoseModifiers() {
        for modifiers: HintClickModifiers in [.command, .shift, .option, [.command, .shift], [.command, .shift, .option]] {
            var hints = session([.press])
            _ = hints.handle(.letter("a"))
            #expect(hints.handle(.enter(modifiers)) == .performing(.click(modifiers), on: 0))
        }
    }

    @Test func controlTapHoversTheSelectionWithoutSwallowingTheModifier() {
        var hints = clickSession()
        #expect(hints.handle(.controlTap) == HintStep(swallow: false, redraw: false, perform: nil, next: .stay))
        _ = hints.handle(.letter("g"))
        #expect(hints.handle(.controlTap) == HintStep(
            swallow: false, redraw: false, perform: HintPerformance(action: .hover, target: 4), next: .end
        ))
    }

    @Test func escapeAndTheHintShortcutEndAndAreSwallowed() {
        var hints = clickSession()
        #expect(hints.handle(.escape) == .cancelled)
        var again = clickSession()
        _ = again.handle(.letter("a"))
        #expect(again.handle(.hintShortcut) == .cancelled)
    }

    @Test func otherChordsEndAndPassThrough() {
        var hints = clickSession()
        _ = hints.handle(.letter("a"))
        #expect(hints.handle(.passThroughChord) == .passedThroughAndEnded)
    }

    @Test func otherKeysAreSwallowedAndIgnored() {
        var hints = clickSession()
        #expect(hints.handle(.other) == .ignored)
    }
}

struct HintCaptureTests {
    @Test func keysTypedWhileScanningReplayInOrder() {
        var capture = HintCapture.started
        #expect(capture.handle(.letter("l")) == .ignored)
        #expect(capture.handle(.letter("s")) == .ignored)
        #expect(capture.handle(.enter([])) == .ignored)
        #expect(capture.handle(.letter("a")) == .ignored)
        let steps = capture.scanFinished(defaultActions: Array(repeating: .press, count: 10))
        #expect(steps == [.redrawn, .redrawn, .performing(.defaultAction, on: 9)])
    }

    @Test func replayKeepsSessionStateWhenNothingEnds() {
        var capture = HintCapture.started
        _ = capture.handle(.letter("l"))
        #expect(capture.handle(.controlTap) == HintStep(swallow: false, redraw: false, perform: nil, next: .stay))
        _ = capture.handle(.backspace)
        _ = capture.handle(.letter("d"))
        let steps = capture.scanFinished(defaultActions: Array(repeating: .click, count: 10))
        #expect(steps.allSatisfy { $0.next == .stay })
        #expect(capture.session?.selection == 2)
        #expect(capture.session?.typed == "")
    }

    @Test func bufferedEnterTwiceDoubleClicks() {
        var capture = HintCapture.started
        for key in [HintKey.letter("a"), .enter([]), .enter([])] { _ = capture.handle(key) }
        let steps = capture.scanFinished(defaultActions: [.click, .click])
        #expect(steps == [
            .redrawn,
            .performing(.defaultAction, on: 0, then: .awaitSecondClick),
            .performing(.secondClickOfDouble, on: 0),
        ])
    }

    @Test func endingKeysActImmediatelyWhileScanning() {
        var capture = HintCapture.started
        _ = capture.handle(.letter("a"))
        #expect(capture.handle(.escape) == .cancelled)
        #expect(capture.handle(.hintShortcut) == .cancelled)
        #expect(capture.handle(.passThroughChord) == .passedThroughAndEnded)
    }

    @Test func doubleClickExpiryRequiresAnActiveAwaitingSession() {
        var capture = HintCapture.started
        let scanning = capture.doubleClickWindowExpired()
        _ = capture.handle(.letter("a"))
        _ = capture.handle(.enter([]))
        _ = capture.scanFinished(defaultActions: [.click])
        let awaiting = capture.doubleClickWindowExpired()
        #expect(!scanning)
        #expect(awaiting)
    }

    @Test func targetsBeyondLabelCapacityAreDropped() {
        let session = HintSession(defaultActions: Array(repeating: .click, count: 800))
        #expect(session.labels.count == 729)
        #expect(session.badges.count == 729)
    }
}
