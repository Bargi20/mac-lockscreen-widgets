// Draws the Bacheca app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (from the repository root)
//
// The artwork follows the macOS icon template: an 824 pt rounded square ("squircle")
// centered on a 1024 pt canvas, with a soft shadow. Inside: a dusk sky, four glass
// widget tiles and a padlock, like widgets on the lock screen.
import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocusFlipped(true)
    defer { image.unlockFocus() }
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // Drop shadow under the squircle.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x2A3870).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    // Dusk sky, top to bottom.
    NSGradient(colors: [color(0x1F2B5C), color(0x6A4C8C), color(0xE58C6A)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: 90)
    // Soft sun glow near the horizon.
    NSGradient(colors: [color(0xFFD08A, 0.55), color(0xFFD08A, 0)])!
        .draw(fromCenter: CGPoint(x: 512, y: 860), radius: 0, toCenter: CGPoint(x: 512, y: 860), radius: 420, options: [])

    // Padlock at the top, where the lock screen shows it.
    if let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 120, weight: .semibold)) {
        let tinted = NSImage(size: lock.size, flipped: false) { rect in
            lock.draw(in: rect)
            NSColor.white.withAlphaComponent(0.92).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let size = tinted.size
        tinted.draw(in: CGRect(x: 512 - size.width / 2, y: 188, width: size.width, height: size.height))
    }

    // Four glass widget tiles: one large, two small, one wide.
    let gap: CGFloat = 26
    let unit: CGFloat = 170
    let left: CGFloat = 512 - (unit * 3 + gap * 2) / 2
    let top: CGFloat = 400
    let tiles = [
        CGRect(x: left, y: top, width: unit * 2 + gap, height: unit),                    // wide
        CGRect(x: left + (unit + gap) * 2, y: top, width: unit, height: unit),            // small
        CGRect(x: left, y: top + unit + gap, width: unit, height: unit),                  // small
        CGRect(x: left + unit + gap, y: top + unit + gap, width: unit * 2 + gap, height: unit), // wide
    ]
    for (i, tile) in tiles.enumerated() {
        let path = NSBezierPath(roundedRect: tile, xRadius: 40, yRadius: 40)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = .black.withAlphaComponent(0.18)
        glow.shadowBlurRadius = 18
        glow.shadowOffset = NSSize(width: 0, height: -6)
        glow.set()
        color(0xFFFFFF, 0.22).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        // Bright top edge, like light catching glass.
        NSGradient(colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0.04)])!.draw(in: path, angle: 90)
        color(0xFFFFFF, 0.55).setStroke()
        path.lineWidth = 3
        path.stroke()

        // A hint of content in each tile.
        NSColor.white.withAlphaComponent(0.9).setFill()
        switch i {
        case 0: // weather: sun and a bar
            NSBezierPath(ovalIn: CGRect(x: tile.minX + 34, y: tile.minY + 40, width: 64, height: 64)).fill()
            NSBezierPath(roundedRect: CGRect(x: tile.minX + 128, y: tile.minY + 56, width: 170, height: 30), xRadius: 15, yRadius: 15).fill()
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: CGRect(x: tile.minX + 128, y: tile.minY + 102, width: 110, height: 22), xRadius: 11, yRadius: 11).fill()
        case 1: // battery ring
            let ring = NSBezierPath()
            ring.appendArc(withCenter: CGPoint(x: tile.midX, y: tile.midY), radius: 52, startAngle: -90, endAngle: 200)
            ring.lineWidth = 18
            ring.lineCapStyle = .round
            color(0x30D158).setStroke()
            ring.stroke()
        case 2: // clock hands
            let hands = NSBezierPath()
            hands.move(to: CGPoint(x: tile.midX, y: tile.midY))
            hands.line(to: CGPoint(x: tile.midX, y: tile.midY - 52))
            hands.move(to: CGPoint(x: tile.midX, y: tile.midY))
            hands.line(to: CGPoint(x: tile.midX + 40, y: tile.midY + 18))
            hands.lineWidth = 14
            hands.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.9).setStroke()
            hands.stroke()
            color(0xFF9F0A).setFill()
            NSBezierPath(ovalIn: CGRect(x: tile.midX - 11, y: tile.midY - 11, width: 22, height: 22)).fill()
        default: // calendar: today circled in red
            color(0xFF453A).setFill()
            NSBezierPath(ovalIn: CGRect(x: tile.minX + 34, y: tile.midY - 42, width: 84, height: 84)).fill()
            NSColor.white.withAlphaComponent(0.85).setFill()
            for row in 0..<2 {
                NSBezierPath(roundedRect: CGRect(x: tile.minX + 150, y: tile.midY - 34 + CGFloat(row) * 44, width: 190 - CGFloat(row) * 60, height: 24),
                             xRadius: 12, yRadius: 12).fill()
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    // Thin inner edge around the squircle.
    color(0xFFFFFF, 0.18).setStroke()
    shape.lineWidth = 2
    shape.stroke()
    return image
}

func png(_ image: NSImage, size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let icon = drawIcon()
for base in [16, 32, 128, 256, 512] {
    try png(icon, size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(icon, size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try png(icon, size: 1024).write(to: URL(fileURLWithPath: "docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
