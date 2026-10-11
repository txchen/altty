import AppKit
import QuartzCore

struct HintOverlayItem: Equatable, Sendable {
    let label: String
    let typedCount: Int
    /// The target's frame in AX global coordinates.
    let frame: CGRect
    let isSelected: Bool
}

@MainActor
protocol HintOverlay: AnyObject {
    func show(_ items: [HintOverlayItem])
    func hide()
}

/// Places items on the screen holding their midpoint, in that screen's local
/// Cocoa coordinates.
enum HintOverlayLayout {
    struct Placement: Equatable {
        let item: HintOverlayItem
        let frame: CGRect
    }

    static func placements(
        _ items: [HintOverlayItem],
        screenFrames: [CGRect],
        primaryScreenHeight: CGFloat
    ) -> [Int: [Placement]] {
        var result: [Int: [Placement]] = [:]
        for item in items {
            let frame = HintGeometry.flipped(item.frame, primaryScreenHeight: primaryScreenHeight)
            let midpoint = CGPoint(x: frame.midX, y: frame.midY)
            guard let screen = screenFrames.firstIndex(where: { $0.contains(midpoint) }) else { continue }
            let origin = screenFrames[screen].origin
            result[screen, default: []].append(
                Placement(item: item, frame: frame.offsetBy(dx: -origin.x, dy: -origin.y))
            )
        }
        return result
    }

    /// A badge sits on the element's top-left corner, kept inside its screen.
    static func badgeFrame(size: CGSize, element: CGRect, screenSize: CGSize) -> CGRect {
        let x = min(max(element.minX, 0), max(screenSize.width - size.width, 0))
        let y = min(max(element.maxY - size.height, 0), max(screenSize.height - size.height, 0))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

@MainActor
final class PanelHintOverlay: HintOverlay {
    private var panels: [Int: HintOverlayPanel] = [:]

    func show(_ items: [HintOverlayItem]) {
        let screens = NSScreen.screens
        let placements = HintOverlayLayout.placements(
            items,
            screenFrames: screens.map(\.frame),
            primaryScreenHeight: HintGeometry.primaryScreenHeight
        )
        for (index, panel) in panels where placements[index] == nil || panel.frame != screens[safe: index]?.frame {
            panel.orderOut(nil)
            panels[index] = nil
        }
        for (index, group) in placements {
            let screen = screens[index]
            let panel = panels[index] ?? HintOverlayPanel(screen: screen)
            panels[index] = panel
            panel.render(group, scale: screen.backingScaleFactor)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
    }
}

private final class HintOverlayPanel: NSPanel {
    private static let badgeColor = NSColor(red: 1, green: 0.84, blue: 0, alpha: 0.95).cgColor
    private static let selectedBadgeColor = NSColor(red: 0.3, green: 0.85, blue: 0.35, alpha: 0.95).cgColor
    private static let outlineColor = NSColor(red: 0.55, green: 1, blue: 0.55, alpha: 1).cgColor
    private static let borderColor = NSColor(white: 0.45, alpha: 1).cgColor
    private static let font = NSFont.boldSystemFont(ofSize: 11)
    private static let padding = CGSize(width: 4, height: 1)

    private let root = CALayer()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        root.frame = view.bounds
        view.layer?.addSublayer(root)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func render(_ placements: [HintOverlayLayout.Placement], scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.sublayers = nil
        for placement in placements where placement.item.isSelected {
            let outline = CALayer()
            outline.frame = placement.frame.insetBy(dx: -2, dy: -2)
            outline.borderColor = Self.outlineColor
            outline.borderWidth = 2
            outline.cornerRadius = 3
            root.addSublayer(outline)
        }
        for placement in placements {
            root.addSublayer(badge(for: placement, scale: scale))
        }
    }

    private func badge(for placement: HintOverlayLayout.Placement, scale: CGFloat) -> CALayer {
        let text = Self.attributedLabel(placement.item)
        let textSize = text.size()
        let size = CGSize(
            width: ceil(textSize.width) + Self.padding.width * 2,
            height: ceil(textSize.height) + Self.padding.height * 2
        )
        let badge = CALayer()
        badge.frame = HintOverlayLayout.badgeFrame(size: size, element: placement.frame, screenSize: root.bounds.size)
        badge.backgroundColor = placement.item.isSelected ? Self.selectedBadgeColor : Self.badgeColor
        badge.borderColor = Self.borderColor
        badge.borderWidth = 1
        badge.cornerRadius = 3
        let label = CATextLayer()
        label.string = text
        label.contentsScale = scale
        label.frame = CGRect(origin: CGPoint(x: Self.padding.width, y: Self.padding.height), size: textSize)
        badge.addSublayer(label)
        return badge
    }

    private static func attributedLabel(_ item: HintOverlayItem) -> NSAttributedString {
        let label = item.label.uppercased()
        let typed = label.prefix(item.typedCount)
        let text = NSMutableAttributedString(
            string: String(typed),
            attributes: [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(0.35)]
        )
        text.append(NSAttributedString(
            string: String(label.dropFirst(item.typedCount)),
            attributes: [.font: font, .foregroundColor: NSColor.black]
        ))
        return text
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
