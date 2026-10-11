import ApplicationServices
import CoreGraphics
import Testing
@testable import Altty

struct HintActionPlanTests {
    @Test func defaultActionsUseAccessibilityForPressAndRaiseOnly() {
        #expect(HintActionPlan(.defaultAction, defaultAction: .press)
            == .accessibility(action: kAXPressAction, bringsAppForward: false, fallback: .click([])))
        #expect(HintActionPlan(.defaultAction, defaultAction: .raise)
            == .accessibility(action: kAXRaiseAction, bringsAppForward: true, fallback: .click([])))
        #expect(HintActionPlan(.defaultAction, defaultAction: .click) == .pointer(.click([])))
    }

    @Test func modifierRightDoubleAndHoverAreAlwaysSynthesized() {
        for defaultAction in [HintDefaultAction.press, .raise, .click] {
            #expect(HintActionPlan(.click(.command), defaultAction: defaultAction) == .pointer(.click(.command)))
            #expect(HintActionPlan(.rightClick, defaultAction: defaultAction) == .pointer(.rightClick))
            #expect(HintActionPlan(.secondClickOfDouble, defaultAction: defaultAction) == .pointer(.secondClickOfDouble))
            #expect(HintActionPlan(.hover, defaultAction: defaultAction) == .pointer(.hover))
        }
    }

    @Test func onlyARefusedAccessibilityActionFallsBackToAClick() {
        #expect(!HintActionPlan.shouldFallBack(after: .success))
        #expect(!HintActionPlan.shouldFallBack(after: .cannotComplete))
        #expect(HintActionPlan.shouldFallBack(after: .actionUnsupported))
        #expect(HintActionPlan.shouldFallBack(after: .invalidUIElement))
    }

    @Test func clicksMoveThenPressWithTheirModifiers() {
        let events = HintPointerGesture.click([.command, .shift]).events
        #expect(events.map(\.type) == [.mouseMoved, .leftMouseDown, .leftMouseUp])
        #expect(events.dropFirst().allSatisfy { $0.flags == [.maskCommand, .maskShift] && $0.clickState == 1 })
        #expect(events.first?.flags == [])
    }

    @Test func rightClickUsesTheRightButton() {
        let events = HintPointerGesture.rightClick.events
        #expect(events.map(\.type) == [.mouseMoved, .rightMouseDown, .rightMouseUp])
        #expect(events.dropFirst().allSatisfy { $0.button == .right })
    }

    @Test func theSecondClickOfADoubleStaysInPlaceWithClickStateTwo() {
        let events = HintPointerGesture.secondClickOfDouble.events
        #expect(events.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(events.allSatisfy { $0.clickState == 2 })
    }

    @Test func hoverOnlyMoves() {
        #expect(HintPointerGesture.hover.events.map(\.type) == [.mouseMoved])
    }
}
