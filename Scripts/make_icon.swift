// Renders the app icon into an .iconset folder: swift make_icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let body = NSRect(x: s * 0.08, y: s * 0.2, width: s * 0.84, height: s * 0.6)

    // Wooden case
    let wood = NSBezierPath(roundedRect: body, xRadius: s * 0.09, yRadius: s * 0.09)
    NSGradient(colors: [NSColor(red: 0.55, green: 0.24, blue: 0.05, alpha: 1),
                        NSColor(red: 0.88, green: 0.5, blue: 0.14, alpha: 1),
                        NSColor(red: 0.55, green: 0.24, blue: 0.05, alpha: 1)])!.draw(in: wood, angle: 0)

    // LCD
    let lcd = body.insetBy(dx: s * 0.07, dy: s * 0.07)
    let screen = NSBezierPath(roundedRect: lcd, xRadius: s * 0.03, yRadius: s * 0.03)
    NSGradient(colors: [NSColor(red: 0.03, green: 0.05, blue: 0.1, alpha: 1),
                        NSColor(red: 0.13, green: 0.18, blue: 0.29, alpha: 1)])!.draw(in: screen, angle: 90)

    let text = "7:00" as NSString
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(red: 0.6, green: 0.75, blue: 1, alpha: 0.9)
    shadow.shadowBlurRadius = s * 0.03
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: s * 0.28, weight: .medium),
        .foregroundColor: NSColor(red: 0.82, green: 0.89, blue: 1, alpha: 1),
        .shadow: shadow,
    ]
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: lcd.midX - size.width / 2, y: lcd.midY - size.height / 2), withAttributes: attrs)

    // Feet
    NSColor(white: 0.25, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.18, y: s * 0.14, width: s * 0.12, height: s * 0.08), xRadius: s * 0.02, yRadius: s * 0.02).fill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.7, y: s * 0.14, width: s * 0.12, height: s * 0.08), xRadius: s * 0.02, yRadius: s * 0.02).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
