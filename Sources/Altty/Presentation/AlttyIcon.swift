import AppKit

/// A template image remains legible in both light and dark menu bars.
@MainActor enum AlttyIcon {
    static func window(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let scale = bounds.width / 18
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()
            NSColor.labelColor.setStroke()
            let frame = NSBezierPath(roundedRect: NSRect(x: 1, y: 2.5, width: 16, height: 13), xRadius: 2.4, yRadius: 2.4)
            frame.lineWidth = 1.3
            frame.stroke()
            let divider = NSBezierPath()
            divider.move(to: .init(x: 1.5, y: 10.5))
            divider.line(to: .init(x: 16.5, y: 10.5))
            divider.lineWidth = 0.8
            divider.stroke()
            NSColor.labelColor.setFill()
            for x: CGFloat in [4, 6.8, 9.6] {
                NSBezierPath(ovalIn: NSRect(x: x - 0.7, y: 12.3, width: 1.4, height: 1.4)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Altty"
        return image
    }
}
