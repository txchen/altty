import AppKit

/// The app icon's tilted card stack as a template, legible in light and dark menu bars.
@MainActor enum AlttyIcon {
    static func window(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let scale = NSAffineTransform()
            scale.scale(by: bounds.width / 18)
            scale.concat()
            let center = NSPoint(x: 9, y: 9)
            let cardRect = NSRect(x: 2.5, y: 4.5, width: 13, height: 9.5)

            func card(rotatedBy degrees: CGFloat, lift: CGFloat = 0) -> NSBezierPath {
                let path = NSBezierPath(roundedRect: cardRect.offsetBy(dx: 0, dy: lift), xRadius: 2, yRadius: 2)
                let transform = NSAffineTransform()
                transform.translateX(by: center.x, yBy: center.y)
                transform.rotate(byDegrees: degrees)
                transform.translateX(by: -center.x, yBy: -center.y)
                path.transform(using: transform as AffineTransform)
                return path
            }

            NSColor.labelColor.setFill()
            NSColor.labelColor.setStroke()
            for (degrees, lift): (CGFloat, CGFloat) in [(18, 2.2), (6, 1.1)] {
                let rear = card(rotatedBy: degrees, lift: lift)
                rear.lineWidth = 1.1
                rear.stroke()
            }
            // The front card and a thin margin around it erase the rear outlines,
            // so the stack still reads as separate cards at menu bar size.
            let front = card(rotatedBy: -8)
            NSGraphicsContext.current?.compositingOperation = .clear
            front.fill()
            front.lineWidth = 1.6
            front.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            front.fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: -8)
            transform.translateX(by: -center.x, yBy: -center.y)
            for x: CGFloat in [5, 7.2, 9.4] {
                let dot = NSBezierPath(ovalIn: NSRect(x: x - 0.7, y: 11.1, width: 1.4, height: 1.4))
                dot.transform(using: transform as AffineTransform)
                dot.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Altty"
        return image
    }
}
