import AppKit

func color(_ hex: Int) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func withShadow(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: dy)
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func rotated(_ degrees: CGFloat, around point: CGPoint, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: point.x, yBy: point.y)
    transform.rotate(byDegrees: degrees)
    transform.translateX(by: -point.x, yBy: -point.y)
    transform.concat()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func card(_ rect: CGRect, _ fill: NSColor) {
    withShadow(blur: 30, dy: -14, alpha: 0.24) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 56, yRadius: 56).fill()
    }
    NSColor.white.withAlphaComponent(0.85).setFill()
    for index in 0..<3 {
        NSBezierPath(ovalIn: CGRect(x: rect.minX + 44 + CGFloat(index) * 50, y: rect.maxY - 76, width: 30, height: 30)).fill()
    }
}

func drawIcon() {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    withShadow(blur: 28, dy: -12, alpha: 0.3) {
        NSGradient(starting: color(0xF6EFE4), ending: color(0xE8DCCB))!.draw(in: tilePath, angle: -90)
    }
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    let center = CGPoint(x: 512, y: 500)
    rotated(14, around: center) { card(CGRect(x: 252, y: 320, width: 520, height: 370), color(0x2E9C8F)) }
    rotated(4, around: center) { card(CGRect(x: 252, y: 300, width: 520, height: 370), color(0xF2A93B)) }
    rotated(-8, around: center) { card(CGRect(x: 252, y: 280, width: 520, height: 370), color(0xE5574B)) }
    NSGraphicsContext.restoreGraphicsState()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: output.appending(path: "icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: output.appending(path: "icon_\(points)x\(points)@2x.png"))
}
