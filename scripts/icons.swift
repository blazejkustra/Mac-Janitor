// Builds every icon from the two SVG masters in assets/: logo.svg (the mark) and menubar.svg (the glyph).
// Usage: swift scripts/icons.swift build          writes the app icon, menu-bar glyph and site icons
//        swift scripts/icons.swift sheets <dir>   writes the icon and menu-bar review sheets
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("assets")
let logoSVG = try! String(contentsOf: assets.appendingPathComponent("logo.svg"), encoding: .utf8)

func image(svg: String) -> NSImage {
    NSImage(data: Data(svg.utf8))!
}

func bitmap(_ pixels: Int, _ draw: (CGRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    draw(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print(url.path)
}

/// The mark on the macOS icon grid: an 824 pt plate in a 1024 canvas with a soft system-like shadow.
func appIcon(_ mark: NSImage, pixels: Int) -> NSBitmapImageRep {
    bitmap(pixels) { canvas in
        let s = canvas.width / 1024
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: NSColor(white: 0, alpha: 0.3).cgColor)
        mark.draw(in: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s))
    }
}

func writeAppIcon(_ mark: NSImage, _ url: URL) {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try! appIcon(mark, pixels: points * scale).representation(using: .png, properties: [:])!
                .write(to: iconset.appendingPathComponent(name))
        }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", url.path]
    try! process.run()
    process.waitUntilExit()
    try? FileManager.default.removeItem(at: iconset)
    print(url.path)
}

/// A one-page PDF of an image at `points`, which AppKit scales crisply.
func writePDF(_ image: NSImage, points: CGFloat, _ url: URL) {
    var box = CGRect(x: 0, y: 0, width: points, height: points)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: box)
    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
    ctx.closePDF()
    print(url.path)
}

func build() {
    let mark = image(svg: logoSVG)
    writeAppIcon(mark, assets.appendingPathComponent("AppIcon.icns"))
    writePDF(mark, points: 64, assets.appendingPathComponent("Logo.pdf"))
    let glyph = image(svg: try! String(contentsOf: assets.appendingPathComponent("menubar.svg"), encoding: .utf8))
    writePDF(glyph, points: 18, assets.appendingPathComponent("MenuBarIcon.pdf"))
    let site = root.appendingPathComponent("site/assets")
    try! logoSVG.write(to: site.appendingPathComponent("logo.svg"), atomically: true, encoding: .utf8)
    writePNG(bitmap(256) { mark.draw(in: $0) }, site.appendingPathComponent("icon-256.png"))
    writePNG(bitmap(64) { mark.draw(in: $0) }, site.appendingPathComponent("favicon.png"))
}

// MARK: - Review sheets

func text(_ s: String, _ p: CGPoint, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight = .regular) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: p)
}

func sheet(width: CGFloat, height: CGFloat, background: NSColor, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func picture(_ rep: NSBitmapImageRep, points: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: points, height: points))
    image.addRepresentation(rep)
    return image
}

/// The icon at 360 pt, with the real 64, 32 and 16 pt renders (at 2x) on dark and light.
func iconSheet(_ url: URL) {
    let mark = image(svg: logoSVG)
    let sizes: [CGFloat] = [64, 32, 16]
    let rep = sheet(width: 440, height: 600, background: NSColor(white: 0.1, alpha: 1)) {
        NSColor(white: 0.95, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 440, height: 92).fill()
        mark.draw(in: NSRect(x: 40, y: 200, width: 360, height: 360))
        for y: CGFloat in [120, 14] {
            var x: CGFloat = 40
            for points in sizes {
                picture(appIcon(mark, pixels: Int(points) * 2), points: points).draw(in: NSRect(x: x, y: y, width: points, height: points))
                x += points + 20
            }
        }
    }
    writePNG(rep, url)
}

func symbol(_ name: String, _ color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

/// The glyph, tinted as the menu bar does, beside system items on light and dark bars.
func menubarSheet(_ url: URL) {
    let svg = try! String(contentsOf: assets.appendingPathComponent("menubar.svg"), encoding: .utf8)
    let rep = sheet(width: 640, height: 250, background: NSColor(white: 0.98, alpha: 1)) {
        text("Menu-bar glyph, real size at 2x", CGPoint(x: 30, y: 210), 16, .black, .semibold)
        for (row, dark) in [false, true].enumerated() {
            let bar = NSRect(x: 30, y: 140 - CGFloat(row) * 44, width: 300, height: 28)
            (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 7, yRadius: 7).fill()
            let ink: NSColor = dark ? .white : .black
            let glyph = image(svg: svg.replacingOccurrences(of: "#000", with: dark ? "#fff" : "#000"))
            glyph.draw(in: NSRect(x: bar.minX + 14, y: bar.midY - 9, width: 18, height: 18))
            var x = bar.minX + 48
            for name in ["wifi", "battery.100percent", "switch.2"] {
                guard let item = symbol(name, ink) else { continue }
                item.draw(in: NSRect(x: x, y: bar.midY - item.size.height / 2, width: item.size.width, height: item.size.height))
                x += item.size.width + 16
            }
            text("Tue 9:41", CGPoint(x: x, y: bar.minY + 5), 13, ink, .medium)
        }
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 380, y: 30, width: 160, height: 160), xRadius: 16, yRadius: 16).fill()
        image(svg: svg).draw(in: NSRect(x: 396, y: 46, width: 128, height: 128))
    }
    writePNG(rep, url)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "build":
    build()
case "sheets" where args.count == 2:
    let dir = URL(fileURLWithPath: args[1])
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    iconSheet(dir.appendingPathComponent("icon.png"))
    menubarSheet(dir.appendingPathComponent("menubar-final.png"))
default:
    print("usage: swift scripts/icons.swift build | sheets <dir>")
    exit(2)
}
