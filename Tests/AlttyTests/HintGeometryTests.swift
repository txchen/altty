import CoreGraphics
import Testing
@testable import Altty

struct HintGeometryTests {
    @Test func axRectsFlipAroundThePrimaryScreenHeight() {
        let ax = CGRect(x: 10, y: 20, width: 100, height: 30)
        let cocoa = HintGeometry.flipped(ax, primaryScreenHeight: 900)
        #expect(cocoa == CGRect(x: 10, y: 850, width: 100, height: 30))
        #expect(HintGeometry.flipped(cocoa, primaryScreenHeight: 900) == ax)
    }

    @Test func screensAboveAndBelowThePrimaryMapToNegativeAndLargeAXOrigins() {
        let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
        let below = CGRect(x: 200, y: -1080, width: 1920, height: 1080)
        #expect(HintGeometry.flipped(above, primaryScreenHeight: 900).origin == CGPoint(x: 0, y: -900))
        #expect(HintGeometry.flipped(below, primaryScreenHeight: 900).origin == CGPoint(x: 200, y: 900))
    }

    @Test func itemsLandOnTheScreenHoldingTheirMidpointInLocalCoordinates() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 200, width: 800, height: 600),
        ]
        func item(_ label: String, _ frame: CGRect) -> HintOverlayItem {
            HintOverlayItem(label: label, typedCount: 0, frame: frame, isSelected: false)
        }
        let primary = item("a", CGRect(x: 10, y: 10, width: 20, height: 20))
        let secondary = item("s", CGRect(x: 1100, y: 100, width: 40, height: 20))
        let nowhere = item("d", CGRect(x: 3000, y: 10, width: 20, height: 20))
        let placements = HintOverlayLayout.placements(
            [primary, secondary, nowhere], screenFrames: screens, primaryScreenHeight: 800
        )
        #expect(placements[0] == [.init(item: primary, frame: CGRect(x: 10, y: 770, width: 20, height: 20))])
        #expect(placements[1] == [.init(item: secondary, frame: CGRect(x: 100, y: 480, width: 40, height: 20))])
        #expect(placements.count == 2)
    }

    @Test func badgesSitOnTheTopLeftCornerAndStayOnScreen() {
        let size = CGSize(width: 20, height: 14)
        let screen = CGSize(width: 1000, height: 800)
        #expect(HintOverlayLayout.badgeFrame(size: size, element: CGRect(x: 100, y: 100, width: 50, height: 50),
                                             screenSize: screen).origin == CGPoint(x: 100, y: 136))
        #expect(HintOverlayLayout.badgeFrame(size: size, element: CGRect(x: -10, y: 790, width: 50, height: 30),
                                             screenSize: screen).origin == CGPoint(x: 0, y: 786))
        #expect(HintOverlayLayout.badgeFrame(size: size, element: CGRect(x: 995, y: 0, width: 5, height: 5),
                                             screenSize: screen).origin == CGPoint(x: 980, y: 0))
    }
}
