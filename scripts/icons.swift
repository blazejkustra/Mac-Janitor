// Draws the menu-bar glyph and app icon candidates and writes the ones the app ships.
// Usage: swift scripts/icons.swift menubar|logos|appicon <out-dir>
import AppKit

// MARK: - Glyphs

/// A monochrome 18 pt menu-bar glyph, drawn in black for a template image.
struct Glyph {
    let name: String
    let draw: (CGContext) -> Void
}

let size = CGSize(width: 18, height: 18)

func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: CGFloat) -> CGPoint {
    let r = degrees * .pi / 180
    return CGPoint(x: center.x + radius * cos(r), y: center.y + radius * sin(r))
}

func strokeLine(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, width: CGFloat) {
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.strokePath()
}

/// A disk ring with an opening at the top right; what was inside flies out of it.
let sweptDisk = Glyph(name: "Swept disk") { ctx in
    let c = CGPoint(x: 7.7, y: 7.7)
    ctx.setLineWidth(2)
    ctx.setLineCap(.round)
    ctx.addArc(center: c, radius: 6.4, startAngle: 80 * .pi / 180, endAngle: 370 * .pi / 180, clockwise: false)
    ctx.strokePath()
    ctx.fillEllipse(in: CGRect(x: c.x - 2.3, y: c.y - 2.3, width: 4.6, height: 4.6))
    for (distance, radius) in [(9.0, 1.4), (11.4, 1.1), (13.5, 0.85)] as [(CGFloat, CGFloat)] {
        let p = point(c, distance, 45)
        ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// A push broom on a slant with a little dust ahead of it.
let broom = Glyph(name: "Broom") { ctx in
    strokeLine(ctx, CGPoint(x: 16.4, y: 17.2), CGPoint(x: 9.6, y: 9.0), width: 2)
    let collar = CGMutablePath()
    collar.move(to: CGPoint(x: 6.9, y: 11.0))
    collar.addLine(to: CGPoint(x: 11.9, y: 7.0))
    collar.addLine(to: CGPoint(x: 10.9, y: 5.6))
    collar.addLine(to: CGPoint(x: 5.6, y: 9.5))
    collar.closeSubpath()
    let bristles = CGMutablePath()
    bristles.move(to: CGPoint(x: 5.0, y: 8.6))
    bristles.addLine(to: CGPoint(x: 10.3, y: 4.7))
    bristles.addLine(to: CGPoint(x: 8.6, y: 0.6))
    bristles.addLine(to: CGPoint(x: 0.6, y: 5.6))
    bristles.closeSubpath()
    ctx.addPath(collar)
    ctx.addPath(bristles)
    ctx.fillPath()
    for (x, y, r) in [(12.7, 2.0, 1.15), (15.2, 3.3, 0.95), (17.0, 1.5, 0.75)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}

/// A drive whose fill is being swept out of its right side.
let emptyingDrive = Glyph(name: "Emptying drive") { ctx in
    let body = CGRect(x: 1.2, y: 4.2, width: 12.6, height: 9.6)
    ctx.setLineWidth(1.6)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 2.6, cornerHeight: 2.6, transform: nil))
    ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 3.6, y: 6.6, width: 4.2, height: 4.8), cornerWidth: 1, cornerHeight: 1, transform: nil))
    ctx.fillPath()
    for (y, from, to) in [(11.2, 10.0, 17.0), (9.0, 11.4, 16.4), (6.8, 10.0, 15.2)] as [(CGFloat, CGFloat, CGFloat)] {
        strokeLine(ctx, CGPoint(x: from, y: y), CGPoint(x: to, y: y), width: 1.3)
    }
}

let glyphs = [sweptDisk, broom, emptyingDrive]
let shipped = broom

// MARK: - Output

func bitmap(_ pixels: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(origin: .zero, size: pixels))
    context.cgContext.scaleBy(x: scale, y: scale)
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print(url.path)
}

/// A one-page vector PDF, which AppKit scales crisply as a template image.
func writePDF(_ glyph: Glyph, _ url: URL) {
    var box = CGRect(origin: .zero, size: size)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.setFillColor(.black)
    ctx.setStrokeColor(.black)
    glyph.draw(ctx)
    ctx.endPDFPage()
    ctx.closePDF()
    print(url.path)
}

/// Glyph drawn in `color` at `scale` (1 for @1x, 2 for @2x), offset into a larger canvas.
func drawGlyph(_ glyph: Glyph, in ctx: CGContext, at origin: CGPoint, scale: CGFloat, color: NSColor) {
    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(color.cgColor)
    ctx.setStrokeColor(color.cgColor)
    glyph.draw(ctx)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func drawText(_ text: String, at p: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
    ]).draw(at: p)
}

func drawSymbol(_ name: String, at p: CGPoint, pointSize: CGFloat, color: NSColor) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    image.draw(at: p, from: .zero, operation: .sourceOver, fraction: 1)
}

/// Each candidate in a light and a dark menu bar beside common system items, at @2x, plus a large view.
func menubarSheet(_ url: URL) {
    let scale: CGFloat = 2
    let rowHeight: CGFloat = 24 * scale
    let width: CGFloat = 900
    let height: CGFloat = 120 + CGFloat(glyphs.count) * 150
    let rep = bitmap(CGSize(width: width, height: height), scale: 1) { ctx in
        NSColor(white: 0.97, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawText("Menu-bar glyph options, real size at @2x", at: CGPoint(x: 40, y: height - 60), size: 26,
                 color: .black, weight: .semibold)
        for (i, glyph) in glyphs.enumerated() {
            let top = height - 110 - CGFloat(i) * 150
            let label = "\(i + 1). \(glyph.name)" + (glyph.name == shipped.name ? "  (shipped)" : "")
            drawText(label, at: CGPoint(x: 40, y: top - 28), size: 18, color: .black, weight: .medium)
            for (j, dark) in [false, true].enumerated() {
                let strip = CGRect(x: 40 + CGFloat(j) * 330, y: top - 40 - rowHeight - 10, width: 310, height: rowHeight)
                (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.9, alpha: 1)).setFill()
                NSBezierPath(roundedRect: strip, xRadius: 10, yRadius: 10).fill()
                let ink: NSColor = dark ? .white : .black
                let y = strip.minY + (rowHeight - 18 * scale) / 2
                drawSymbol("wifi", at: CGPoint(x: strip.minX + 24, y: y + 4), pointSize: 26, color: ink)
                drawGlyph(glyph, in: ctx, at: CGPoint(x: strip.minX + 84, y: y), scale: scale, color: ink)
                drawSymbol("battery.75percent", at: CGPoint(x: strip.minX + 140, y: y + 6), pointSize: 26, color: ink)
                drawText("Tue 9:41", at: CGPoint(x: strip.minX + 210, y: y + 4), size: 26, color: ink)
            }
            let big = CGRect(x: 720, y: top - 140, width: 120, height: 120)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: big, xRadius: 14, yRadius: 14).fill()
            drawGlyph(glyph, in: ctx, at: CGPoint(x: big.minX + 6, y: big.minY + 6), scale: 6, color: .black)
        }
    }
    writePNG(rep, url)
}

// MARK: - App icon

/// One app icon direction: a palette and a foreground drawn on a 1024 canvas.
struct Logo {
    let name: String
    let top: NSColor
    let bottom: NSColor
    let echo: NSColor
    let ink: NSColor
    /// `front` is the cream layer, which carries the detail the echo behind it leaves out.
    let draw: (CGContext, _ fill: NSColor, _ front: Bool) -> Void
}

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255, alpha: alpha)
}

let cream = hex(0xF4EEDF)

/// The glyph's geometry at icon scale, centred in the 1024 canvas.
func glyphSpace(_ ctx: CGContext, scale: CGFloat = 36, offset: CGPoint = CGPoint(x: 188, y: 182)) {
    ctx.translateBy(x: offset.x, y: offset.y)
    ctx.scaleBy(x: scale, y: scale)
}

let broomLogo = Logo(name: "Broom", top: hex(0x24584E), bottom: hex(0x0A1F1B), echo: hex(0x46D6A6), ink: cream) { ctx, fill, front in
    glyphSpace(ctx, scale: 34, offset: CGPoint(x: 214, y: 214))
    ctx.setFillColor(fill.cgColor)
    ctx.setStrokeColor(fill.cgColor)
    broom.draw(ctx)
    guard front else { return }
    ctx.setStrokeColor(hex(0x24584E, 0.28).cgColor)
    for t in [0.2, 0.4, 0.6, 0.8] as [CGFloat] {
        let top = CGPoint(x: 5.0 + (10.3 - 5.0) * t, y: 8.6 + (4.7 - 8.6) * t)
        let bottom = CGPoint(x: 0.6 + (8.6 - 0.6) * t, y: 5.6 + (0.6 - 5.6) * t)
        strokeLine(ctx, CGPoint(x: top.x - (top.x - bottom.x) * 0.15, y: top.y - (top.y - bottom.y) * 0.15),
                   CGPoint(x: bottom.x + (top.x - bottom.x) * 0.12, y: bottom.y + (top.y - bottom.y) * 0.12), width: 0.22)
    }
    ctx.setFillColor(hex(0x46D6A6).cgColor)
    let collar = CGMutablePath()
    collar.move(to: CGPoint(x: 6.9, y: 11.0))
    collar.addLine(to: CGPoint(x: 11.9, y: 7.0))
    collar.addLine(to: CGPoint(x: 11.5, y: 6.45))
    collar.addLine(to: CGPoint(x: 6.4, y: 10.3))
    collar.closeSubpath()
    ctx.addPath(collar)
    ctx.fillPath()
}

let diskLogo = Logo(name: "Swept disk", top: hex(0x30347A), bottom: hex(0x0D0F2B), echo: hex(0x8C95FF), ink: cream) { ctx, fill, _ in
    glyphSpace(ctx, scale: 33, offset: CGPoint(x: 232, y: 232))
    ctx.setFillColor(fill.cgColor)
    ctx.setStrokeColor(fill.cgColor)
    sweptDisk.draw(ctx)
}

let driveLogo = Logo(name: "Emptying drive", top: hex(0x34343A), bottom: hex(0x121214), echo: hex(0xF4B740), ink: cream) { ctx, fill, _ in
    glyphSpace(ctx, scale: 34, offset: CGPoint(x: 204, y: 206))
    ctx.setFillColor(fill.cgColor)
    ctx.setStrokeColor(fill.cgColor)
    emptyingDrive.draw(ctx)
}

let logos = [broomLogo, diskLogo, driveLogo]
let shippedLogo = broomLogo

/// Shadows ignore the transform, so they are scaled to match it by hand.
func setShadow(_ ctx: CGContext, dy: CGFloat, blur: CGFloat, alpha: CGFloat) {
    let scale = ctx.ctm.a
    ctx.setShadow(offset: CGSize(width: 0, height: dy * scale), blur: blur * scale, color: NSColor(white: 0, alpha: alpha).cgColor)
}

/// The macOS icon plate: an 824 pt rounded square with a drop shadow, a vertical gradient and a lit top edge.
func drawPlate(_ logo: Logo, _ ctx: CGContext) {
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    setShadow(ctx, dy: -12, blur: 28, alpha: 0.35)
    ctx.addPath(shape)
    ctx.setFillColor(logo.bottom.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [logo.top.cgColor, logo.bottom.cgColor] as CFArray, locations: [0, 0.85])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
    let glow = CGGradient(colorsSpace: nil, colors: [logo.echo.withAlphaComponent(0.22).cgColor, logo.echo.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 380, y: 360), startRadius: 0, endCenter: CGPoint(x: 380, y: 360),
                           endRadius: 520, options: [])
    let sheen = CGGradient(colorsSpace: nil, colors: [NSColor(white: 1, alpha: 0.16).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.maxY - 140), options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()
}

/// Foreground in three layers: a coloured echo set back and down, a soft shadow, and the cream glyph.
func drawForeground(_ logo: Logo, _ ctx: CGContext) {
    func layer(dx: CGFloat, dy: CGFloat, color: NSColor, front: Bool) {
        ctx.saveGState()
        if front {
            setShadow(ctx, dy: -10, blur: 22, alpha: 0.45)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: dx, y: dy)
        logo.draw(ctx, color, front)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    layer(dx: -26, dy: -26, color: logo.echo.withAlphaComponent(0.75), front: false)
    layer(dx: 0, dy: 0, color: logo.ink, front: true)
}

func drawLogo(_ logo: Logo, _ ctx: CGContext) {
    drawPlate(logo, ctx)
    drawForeground(logo, ctx)
}

func logoBitmap(_ logo: Logo, pixels: Int) -> NSBitmapImageRep {
    bitmap(CGSize(width: pixels, height: pixels), scale: CGFloat(pixels) / 1024) { drawLogo(logo, $0) }
}

/// All directions side by side at 1024 pt scaled down, each with 64, 32 and 16 px renders under it.
func logoSheet(_ url: URL) {
    let width: CGFloat = 1500, height: CGFloat = 760
    let previews = logos.map { logo in [64, 32, 16].map { logoBitmap(logo, pixels: $0) } }
    let rep = bitmap(CGSize(width: width, height: height), scale: 1) { ctx in
        hex(0x18181B).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawText("App icon directions", at: CGPoint(x: 60, y: height - 80), size: 30, color: .white, weight: .semibold)
        for (i, logo) in logos.enumerated() {
            let x = 60 + CGFloat(i) * 480
            ctx.saveGState()
            ctx.translateBy(x: x - 20, y: 180)
            ctx.scaleBy(x: 440 / 1024, y: 440 / 1024)
            drawLogo(logo, ctx)
            ctx.restoreGState()
            let label = "\(i + 1). \(logo.name)" + (logo.name == shippedLogo.name ? "  (shipped)" : "")
            drawText(label, at: CGPoint(x: x, y: 640), size: 20, color: .white, weight: .medium)
            var sx = x
            for preview in previews[i] {
                let px = CGFloat(preview.pixelsWide)
                let image = NSImage(size: NSSize(width: px, height: px))
                image.addRepresentation(preview)
                image.draw(in: NSRect(x: sx, y: 90, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1)
                sx += px + 24
            }
            drawText("64, 32 and 16 px", at: CGPoint(x: x, y: 50), size: 14, color: NSColor(white: 1, alpha: 0.5))
        }
    }
    writePNG(rep, url)
}

/// An .icns from the shipped direction, through an iconset and iconutil.
func writeAppIcon(_ dir: URL) {
    let iconset = dir.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            writePNG(logoBitmap(shippedLogo, pixels: points * scale), iconset.appendingPathComponent(name))
        }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
    try! process.run()
    process.waitUntilExit()
    try? FileManager.default.removeItem(at: iconset)
    print(dir.appendingPathComponent("AppIcon.icns").path)
}

// MARK: - Main

let args = CommandLine.arguments.dropFirst()
guard args.count == 2, let command = args.first, let out = args.last else {
    print("usage: swift scripts/icons.swift menubar|logos|appicon <out-dir>")
    exit(2)
}
let dir = URL(fileURLWithPath: out)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

switch command {
case "menubar":
    writePDF(shipped, dir.appendingPathComponent("MenuBarIcon.pdf"))
    menubarSheet(dir.appendingPathComponent("menubar-options.png"))
case "logos":
    for (i, logo) in logos.enumerated() {
        writePNG(logoBitmap(logo, pixels: 1024), dir.appendingPathComponent("logo-\(i + 1).png"))
    }
    logoSheet(dir.appendingPathComponent("logo-options.png"))
case "appicon":
    writeAppIcon(dir)
    writePNG(logoBitmap(shippedLogo, pixels: 1024), dir.appendingPathComponent("AppIcon-1024.png"))
default:
    print("unknown command \(command)")
    exit(2)
}
