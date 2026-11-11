// Renders the site's backdrop and the video poster.
// Usage: swift scripts/site-art.swift site/assets
import AppKit
import CoreImage

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
}

func context(_ size: CGSize) -> CGContext {
    CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// A wide soft band of light across the canvas, like one pass of a squeegee.
struct Ribbon {
    let from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint
    let width: CGFloat
    let color: CGColor
}

func drawRibbons(_ ribbons: [Ribbon], size: CGSize, blur: Double) -> CIImage {
    let ctx = context(size)
    ctx.setLineCap(.round)
    for r in ribbons {
        ctx.setStrokeColor(r.color)
        ctx.setLineWidth(r.width)
        ctx.move(to: r.from)
        ctx.addCurve(to: r.to, control1: r.c1, control2: r.c2)
        ctx.strokePath()
    }
    return CIImage(cgImage: ctx.makeImage()!).clampedToExtent()
        .applyingGaussianBlur(sigma: blur)
        .cropped(to: CGRect(origin: .zero, size: size))
}

func backdrop(_ size: CGSize) -> CIImage {
    let w = size.width, h = size.height
    let base = context(size)
    base.setFillColor(hex(0x07120F))
    base.fill(CGRect(origin: .zero, size: size))
    let glow = CGGradient(colorsSpace: nil, colors: [hex(0x1E5C4E, 0.9), hex(0x07120F, 0)] as CFArray, locations: [0, 1])!
    base.drawRadialGradient(glow, startCenter: CGPoint(x: w * 0.72, y: h * 0.86), startRadius: 0,
                            endCenter: CGPoint(x: w * 0.72, y: h * 0.86), endRadius: w * 0.62, options: [])
    let low = CGGradient(colorsSpace: nil, colors: [hex(0x0F2E3A, 0.8), hex(0x07120F, 0)] as CFArray, locations: [0, 1])!
    base.drawRadialGradient(low, startCenter: CGPoint(x: w * 0.12, y: h * 0.1), startRadius: 0,
                            endCenter: CGPoint(x: w * 0.12, y: h * 0.1), endRadius: w * 0.5, options: [])
    var image = CIImage(cgImage: base.makeImage()!)

    let soft = drawRibbons([
        Ribbon(from: CGPoint(x: -200, y: h * 0.18), c1: CGPoint(x: w * 0.3, y: h * 0.05), c2: CGPoint(x: w * 0.55, y: h * 0.95),
               to: CGPoint(x: w + 200, y: h * 0.72), width: 260, color: hex(0x2E9C7C, 0.55)),
        Ribbon(from: CGPoint(x: -200, y: h * 0.02), c1: CGPoint(x: w * 0.35, y: h * -0.1), c2: CGPoint(x: w * 0.6, y: h * 0.8),
               to: CGPoint(x: w + 200, y: h * 0.48), width: 180, color: hex(0x1B6B6E, 0.5)),
        Ribbon(from: CGPoint(x: -200, y: h * 0.4), c1: CGPoint(x: w * 0.25, y: h * 0.3), c2: CGPoint(x: w * 0.5, y: h * 1.1),
               to: CGPoint(x: w + 200, y: h * 1.02), width: 120, color: hex(0x5FE3B5, 0.28)),
    ], size: size, blur: 70)
    let sharp = drawRibbons([
        Ribbon(from: CGPoint(x: -200, y: h * 0.21), c1: CGPoint(x: w * 0.3, y: h * 0.08), c2: CGPoint(x: w * 0.55, y: h * 0.98),
               to: CGPoint(x: w + 200, y: h * 0.75), width: 4, color: hex(0xBFF7E2, 0.4)),
        Ribbon(from: CGPoint(x: -200, y: h * 0.05), c1: CGPoint(x: w * 0.35, y: h * -0.07), c2: CGPoint(x: w * 0.6, y: h * 0.83),
               to: CGPoint(x: w + 200, y: h * 0.51), width: 2, color: hex(0x8FE9CC, 0.25)),
    ], size: size, blur: 3)
    image = soft.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    return sharp.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
}

func writeJPEG(_ image: CIImage, _ url: URL) {
    let ci = CIContext()
    let cg = ci.createCGImage(image, from: image.extent)!
    let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.72])!
    try! data.write(to: url)
    print(url.path)
}

/// The panel screenshot centred on the backdrop at 16:9, shown until the demo video exists.
func poster(panel: URL, size: CGSize) -> CIImage {
    let back = backdrop(size)
    let shot = CIImage(contentsOf: panel)!
    let scale = size.height * 0.8 / shot.extent.height
    let placed = shot.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let x = (size.width - placed.extent.width) / 2, y = (size.height - placed.extent.height) / 2
    let moved = placed.transformed(by: CGAffineTransform(translationX: x, y: y))
    let shadow = moved.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.6),
    ]).transformed(by: CGAffineTransform(translationX: 0, y: -24)).applyingGaussianBlur(sigma: 30)
    return moved.composited(over: shadow.composited(over: back)).cropped(to: CGRect(origin: .zero, size: size))
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "site/assets")
writeJPEG(backdrop(CGSize(width: 2400, height: 1500)), out.appendingPathComponent("backdrop.jpg"))
writeJPEG(poster(panel: out.appendingPathComponent("panel-dark.png"), size: CGSize(width: 1920, height: 1080)),
          out.appendingPathComponent("demo-poster.jpg"))
