import AppKit

/// AX reports global rectangles with the origin at the primary display's
/// top-left corner and y growing downwards; Cocoa puts the origin at that
/// display's bottom-left corner with y growing upwards. The flip is its own
/// inverse.
enum HintGeometry {
    static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    @MainActor
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    @MainActor
    static func axScreenFrames() -> [CGRect] {
        let height = primaryScreenHeight
        return NSScreen.screens.map { flipped($0.frame, primaryScreenHeight: height) }
    }
}
