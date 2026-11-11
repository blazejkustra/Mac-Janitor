// Draws the menu-bar glyph candidates and writes the one the app ships.
// Usage: swift scripts/icons.swift menubar <out-dir>
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

// MARK: - Main

let args = CommandLine.arguments.dropFirst()
guard args.count == 2, let command = args.first, let out = args.last else {
    print("usage: swift scripts/icons.swift menubar <out-dir>")
    exit(2)
}
let dir = URL(fileURLWithPath: out)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

switch command {
case "menubar":
    writePDF(shipped, dir.appendingPathComponent("MenuBarIcon.pdf"))
    menubarSheet(dir.appendingPathComponent("menubar-options.png"))
default:
    print("unknown command \(command)")
    exit(2)
}
