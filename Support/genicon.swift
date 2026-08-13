// Standalone icon generator, run via `swift Support/genicon.swift <output-iconset-dir>`.
//
// A macOS-native take on WinDirStat's identity: a lime-green app tile carrying a
// black "file tree" — rooted trunk, tapering branches, and rounded-square blocks
// as leaves (a tree fused with treemap tiles). Original artwork, not their logo.
//
// Strokes are drawn as filled outlines rather than CGContext strokes so every
// limb can taper from thick at the trunk to thin at the tips.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let ink = CGColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)

/// Fills a quadratic Bézier as a tapered ribbon (w0 at the start, w1 at the end).
func taperedQuad(
    _ ctx: CGContext, from p0: CGPoint, to p2: CGPoint, control p1: CGPoint,
    w0: CGFloat, w1: CGFloat, steps: Int = 28
) {
    var left: [CGPoint] = []
    var right: [CGPoint] = []
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let mt = 1 - t
        let x = mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x
        let y = mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        var dx = 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x)
        var dy = 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        let len = max((dx * dx + dy * dy).squareRoot(), 1e-6)
        dx /= len
        dy /= len
        let half = (w0 + (w1 - w0) * t) / 2
        left.append(CGPoint(x: x - dy * half, y: y + dx * half))
        right.append(CGPoint(x: x + dy * half, y: y - dx * half))
    }
    ctx.beginPath()
    ctx.move(to: left[0])
    for p in left.dropFirst() { ctx.addLine(to: p) }
    for p in right.reversed() { ctx.addLine(to: p) }
    ctx.closePath()
    ctx.fillPath()
    // Round off the thin end so tips don't look chopped.
    ctx.fillEllipse(in: CGRect(x: p2.x - w1 / 2, y: p2.y - w1 / 2, width: w1, height: w1))
}

func draw(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: content ≈ 80% of the canvas, squircle corners ≈ 22.5%.
    let inset = s * 0.10
    let square = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = square.width * 0.225
    let tile = CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil)

    let cx = square.midX
    let cy = square.midY
    let R = square.width * 0.42

    // Green tile: vertical gradient, upper-left sheen, soft bottom vignette.
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.74, green: 0.89, blue: 0.10, alpha: 1),
            CGColor(red: 0.60, green: 0.75, blue: 0.0, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: square.midX, y: square.maxY),
                           end: CGPoint(x: square.midX, y: square.minY), options: [])
    let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.83, green: 0.95, blue: 0.30, alpha: 0.9),
            CGColor(red: 0.667, green: 0.831, blue: 0.0, alpha: 0.0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        sheen,
        startCenter: CGPoint(x: square.minX + square.width * 0.32, y: square.maxY - square.height * 0.30),
        startRadius: 0,
        endCenter: CGPoint(x: square.midX, y: square.midY), endRadius: square.width * 0.75, options: []
    )
    let vignette = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.40, green: 0.50, blue: 0.0, alpha: 0.0),
            CGColor(red: 0.40, green: 0.50, blue: 0.0, alpha: 0.35),
        ] as CFArray,
        locations: [0.7, 1]
    )!
    ctx.drawLinearGradient(vignette, start: CGPoint(x: square.midX, y: square.midY),
                           end: CGPoint(x: square.midX, y: square.minY), options: [])
    ctx.restoreGState()

    // Tree, clipped to the tile so nothing spills past the corners.
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    ctx.setFillColor(ink)

    func P(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
        CGPoint(x: cx + fx * R, y: cy + fy * R)  // fy positive = up
    }

    func node(_ fx: CGFloat, _ fy: CGFloat, _ sideFrac: CGFloat) {
        let side = R * sideFrac
        let r = CGRect(x: cx + fx * R - side / 2, y: cy + fy * R - side / 2, width: side, height: side)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: side * 0.28, cornerHeight: side * 0.28, transform: nil))
        ctx.fillPath()
    }

    // The whole tree is mirrored about the vertical centerline.

    // Roots splay out from the base of the trunk.
    let base = P(0.0, -0.80)
    for side: CGFloat in [-1, 1] {
        taperedQuad(ctx, from: base, to: P(side * 0.50, -0.97), control: P(side * 0.26, -0.84),
                    w0: R * 0.23, w1: R * 0.05)
        taperedQuad(ctx, from: base, to: P(side * 0.22, -1.06), control: P(side * 0.12, -0.95),
                    w0: R * 0.17, w1: R * 0.04)
    }

    // Trunk rises into a central hub — the point every branch stems from.
    let hub = P(0.0, 0.06)
    taperedQuad(ctx, from: P(0.0, -0.90), to: hub, control: P(0.0, -0.40), w0: R * 0.42, w1: R * 0.21)

    // Branches: hub → block, tapering as they go.
    func branch(to tip: CGPoint, control: CGPoint, w1: CGFloat = 0.08) {
        taperedQuad(ctx, from: hub, to: tip, control: control, w0: R * 0.185, w1: R * w1)
    }
    branch(to: P(0.0, 0.82), control: P(0.0, 0.42))
    for side: CGFloat in [-1, 1] {
        branch(to: P(side * 0.46, 0.68), control: P(side * 0.28, 0.30))
        branch(to: P(side * 0.69, 0.22), control: P(side * 0.40, 0.02))
        branch(to: P(side * 0.36, -0.28), control: P(side * 0.24, -0.04), w1: 0.075)
    }

    // Solid hub so trunk and branches merge into one clean junction.
    ctx.fillEllipse(in: CGRect(x: hub.x - R * 0.12, y: hub.y - R * 0.12, width: R * 0.24, height: R * 0.24))

    // Rounded-square blocks (treemap tiles as leaves) in mirrored pairs.
    node(0.0, 0.82, 0.50)
    for side: CGFloat in [-1, 1] {
        node(side * 0.46, 0.68, 0.42)
        node(side * 0.69, 0.22, 0.42)
        node(side * 0.36, -0.28, 0.34)
    }

    ctx.restoreGState()
    return ctx.makeImage()
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        guard let img = draw(size: px) else { fatalError("render failed at \(px)px") }
        let suffix = scale == 1 ? "" : "@2x"
        write(img, to: "\(outDir)/icon_\(base)x\(base)\(suffix).png")
    }
}
print("iconset written to \(outDir)")
