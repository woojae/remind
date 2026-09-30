// Renders the app icon to match the control-room theme: a near-black tile
// with a faint grid, reticle corners, an off-white bell and a hot-pink
// status dot. Run by `make`:
//   swift App/mkicon.swift <output.iconset dir>
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let plateColor = NSColor(srgbRed: 0x0a / 255, green: 0x0a / 255, blue: 0x0c / 255, alpha: 1)
let ink = NSColor(srgbRed: 0xe8 / 255, green: 0xe6 / 255, blue: 0xdd / 255, alpha: 1)
let accent = NSColor(srgbRed: 0xff / 255, green: 0x2e / 255, blue: 0x63 / 255, alpha: 1)
let gridColor = NSColor.white.withAlphaComponent(0.07)
let borderColor = NSColor.white.withAlphaComponent(0.16)

func render(_ px: Int) -> Data? {
    let p = CGFloat(px)
    let size = NSSize(width: p, height: p)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    // Plate: the standard macOS rounded-square footprint.
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: p * 0.06, dy: p * 0.06)
    let plate = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    plateColor.setFill()
    plate.fill()

    // Grid, clipped to the plate.
    ctx.saveGState()
    plate.addClip()
    let step = max(p * 0.085, 4)
    let hair = max(p / 512, 0.5)
    gridColor.setStroke()
    var x = rect.minX
    while x <= rect.maxX {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: rect.minY)); line.line(to: NSPoint(x: x, y: rect.maxY))
        line.lineWidth = hair; line.stroke()
        x += step
    }
    var y = rect.minY
    while y <= rect.maxY {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: rect.minX, y: y)); line.line(to: NSPoint(x: rect.maxX, y: y))
        line.lineWidth = hair; line.stroke()
        y += step
    }
    ctx.restoreGState()

    // Thin border and reticle corners.
    if px >= 32 {
        borderColor.setStroke()
        plate.lineWidth = max(p / 256, 1)
        plate.stroke()

        let inset = rect.insetBy(dx: p * 0.16, dy: p * 0.16)
        let arm = p * 0.07
        let corners = NSBezierPath()
        corners.lineWidth = max(p / 200, 1)
        for (cx, cy, sx, sy) in [(inset.minX, inset.minY, 1.0, 1.0), (inset.maxX, inset.minY, -1.0, 1.0),
                                 (inset.minX, inset.maxY, 1.0, -1.0), (inset.maxX, inset.maxY, -1.0, -1.0)] {
            corners.move(to: NSPoint(x: cx, y: cy + arm * sy))
            corners.line(to: NSPoint(x: cx, y: cy))
            corners.line(to: NSPoint(x: cx + arm * sx, y: cy))
        }
        ink.withAlphaComponent(0.55).setStroke()
        corners.stroke()
    }

    // Bell.
    let config = NSImage.SymbolConfiguration(pointSize: p * 0.34, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "bell", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            ink.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let s = tinted.size
        tinted.draw(at: NSPoint(x: p / 2 - s.width / 2, y: p / 2 - s.height / 2),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }

    // Status dot, top right of the bell, with a soft glow.
    let dot = p * 0.09
    let dotRect = NSRect(x: p * 0.61, y: p * 0.61, width: dot, height: dot)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: p * 0.04, color: accent.withAlphaComponent(0.9).cgColor)
    accent.setFill()
    NSBezierPath(rect: dotRect).fill()
    ctx.restoreGState()

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = size
    return rep.representation(using: .png, properties: [:])
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    guard let data = render(px) else { fputs("could not render \(px)px\n", stderr); exit(1) }
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
