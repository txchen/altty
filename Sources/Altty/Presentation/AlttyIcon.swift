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
            // Only draw the exposed edge of the rear window, so the template
            // stays transparent without lines showing through the front window.
            let rear = NSBezierPath()
            rear.move(to: .init(x: 4, y: 14.5))
            rear.line(to: .init(x: 4, y: 15))
            rear.curve(to: .init(x: 6, y: 17), controlPoint1: .init(x: 4, y: 16.1), controlPoint2: .init(x: 4.9, y: 17))
            rear.line(to: .init(x: 15, y: 17))
            rear.curve(to: .init(x: 17, y: 15), controlPoint1: .init(x: 16.1, y: 17), controlPoint2: .init(x: 17, y: 16.1))
            rear.line(to: .init(x: 17, y: 6))
            rear.curve(to: .init(x: 15.5, y: 4), controlPoint1: .init(x: 17, y: 4.9), controlPoint2: .init(x: 16.6, y: 4))
            rear.lineWidth = 1.15
            rear.lineCapStyle = .round
            rear.stroke()

            let frame = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 13, height: 12), xRadius: 2, yRadius: 2)
            frame.lineWidth = 1.15
            frame.stroke()
            let divider = NSBezierPath()
            divider.move(to: .init(x: 1.5, y: 9))
            divider.line(to: .init(x: 13.5, y: 9))
            divider.lineWidth = 0.7
            divider.stroke()
            NSColor.labelColor.setFill()
            for x: CGFloat in [3.5, 5.7, 7.9] {
                NSBezierPath(ovalIn: NSRect(x: x - 0.55, y: 10.45, width: 1.1, height: 1.1)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Altty"
        return image
    }
}
