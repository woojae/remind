// Renders the app icon: the site's logo badge — a white tile, tilted a few
// degrees, with a bell drawn on it — sitting on the sky-blue desktop. Run by
// `make`:
//   swift App/mkicon.swift <output.iconset dir>
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let desktop = NSColor(srgbRed: 0x6b / 255, green: 0x9b / 255, blue: 0xd2 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x13 / 255, green: 0x14 / 255, blue: 0x17 / 255, alpha: 1)

func render(_ px: Int) -> Data? {
    let p = CGFloat(px)
    let size = NSSize(width: p, height: p)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    // Desktop: the standard macOS rounded-square footprint.
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: p * 0.06, dy: p * 0.06)
    let plate = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    desktop.setFill()
    plate.fill()

    // Badge: white tile rotated -4°, with a soft drop shadow.
    ctx.saveGState()
    ctx.translateBy(x: p / 2, y: p / 2)
    ctx.rotate(by: -4 * .pi / 180)
    let tile = p * 0.56
    let tileRect = NSRect(x: -tile / 2, y: -tile / 2, width: tile, height: tile)
    ctx.setShadow(offset: CGSize(width: 0, height: -p * 0.025), blur: p * 0.06,
                  color: NSColor.black.withAlphaComponent(0.28).cgColor)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: tileRect, xRadius: tile * 0.28, yRadius: tile * 0.28).fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let config = NSImage.SymbolConfiguration(pointSize: p * 0.30, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "bell", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            ink.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let s = tinted.size
        tinted.draw(at: NSPoint(x: -s.width / 2, y: -s.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
    }
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
