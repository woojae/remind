// Renders the app icon: a rounded orange tile with a bell. Run by `make`:
//   swift App/mkicon.swift <output.iconset dir>
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: CGFloat(px) * 0.06, dy: CGFloat(px) * 0.06)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    path.addClip()
    let gradient = NSGradient(starting: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.20, alpha: 1),
                              ending: NSColor(calibratedRed: 0.93, green: 0.36, blue: 0.10, alpha: 1))!
    gradient.draw(in: rect, angle: -90)
    ctx.resetClip()

    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.52, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let s = tinted.size
        let origin = NSPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }
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
