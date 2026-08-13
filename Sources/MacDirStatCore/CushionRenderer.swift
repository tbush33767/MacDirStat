import CoreGraphics
import Foundation

/// WinDirStat-style cushion treemap renderer (van Wijk & van de Wetering).
///
/// Each nested rectangle adds a parabolic ridge to a height field; only the
/// gradient matters for diffuse lighting, so the recursion carries just four
/// quadratic coefficients. Leaves are rasterized per pixel into an RGBA8
/// buffer with the extension color modulated by the surface lighting.
public enum CushionRenderer {
    // WinDirStat default parameters.
    static let baseHeight = 0.75
    static let heightFalloff = 0.75
    static let ambient = 0.15
    // Light direction (-1, -1, 10), normalized.
    static let lightX = -1.0 / 10.0995
    static let lightY = -1.0 / 10.0995
    static let lightZ = 10.0 / 10.0995

    /// Per-axis quadratic surface: z = a·t² + b·t (+ c, irrelevant to lighting).
    struct Surface {
        var ax = 0.0, bx = 0.0, ay = 0.0, by = 0.0

        mutating func addXRidge(from x1: Double, to x2: Double, height h: Double) {
            guard x2 > x1 else { return }
            ax -= 4 * h / (x2 - x1)
            bx += 4 * h * (x1 + x2) / (x2 - x1)
        }

        mutating func addYRidge(from y1: Double, to y2: Double, height h: Double) {
            guard y2 > y1 else { return }
            ay -= 4 * h / (y2 - y1)
            by += 4 * h * (y1 + y2) / (y2 - y1)
        }
    }

    /// Renders the laid-out tree into a fresh CGImage of `size` (1x pixels).
    /// `layout` must have been run for the same size beforehand.
    public static func render(root: FSNode, size: CGSize, palette: Palette) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        pixels.withUnsafeMutableBufferPointer { buf in
            var surface = Surface()
            renderNode(root, depth: 0, surface: &surface, palette: palette,
                       buf: buf, width: width, height: height)
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func renderNode(
        _ node: FSNode,
        depth: Int,
        surface: inout Surface,
        palette: Palette,
        buf: UnsafeMutableBufferPointer<UInt8>,
        width: Int,
        height: Int
    ) {
        let rect = node.rect
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }

        var s = surface
        let h = baseHeight * pow(heightFalloff, Double(depth))
        s.addXRidge(from: Double(rect.minX), to: Double(rect.maxX), height: h)
        s.addYRidge(from: Double(rect.minY), to: Double(rect.maxY), height: h)

        let renderableChildren = node.isDirectory
            ? node.children.filter { !$0.rect.isNull }
            : []

        if renderableChildren.isEmpty {
            // Leaf (or a directory too small to subdivide): rasterize.
            let color = node.isDirectory
                ? Palette.directoryColor
                : palette.color(forExtension: node.fileExtension)
            rasterize(rect: rect, surface: s, color: color,
                      buf: buf, width: width, height: height)
        } else {
            for child in renderableChildren {
                renderNode(child, depth: depth + 1, surface: &s, palette: palette,
                           buf: buf, width: width, height: height)
            }
        }
    }

    private static func rasterize(
        rect: CGRect,
        surface s: Surface,
        color: RGB,
        buf: UnsafeMutableBufferPointer<UInt8>,
        width: Int,
        height: Int
    ) {
        let x0 = max(0, Int(rect.minX.rounded(.down)))
        let x1 = min(width, Int(rect.maxX.rounded(.up)))
        let y0 = max(0, Int(rect.minY.rounded(.down)))
        let y1 = min(height, Int(rect.maxY.rounded(.up)))
        guard x1 > x0, y1 > y0 else { return }

        let r = Double(color.r), g = Double(color.g), b = Double(color.b)

        for py in y0..<y1 {
            let fy = Double(py) + 0.5
            let ny = -(2 * s.ay * fy + s.by)
            var idx = (py * width + x0) * 4
            for px in x0..<x1 {
                let fx = Double(px) + 0.5
                let nx = -(2 * s.ax * fx + s.bx)
                // Diffuse term: N·L with N = (nx, ny, 1) normalized.
                let dot = (nx * lightX + ny * lightY + lightZ)
                    / (nx * nx + ny * ny + 1).squareRoot()
                let brightness = ambient + max(0, 0.85 * dot)
                buf[idx] = UInt8(min(255, r * brightness))
                buf[idx + 1] = UInt8(min(255, g * brightness))
                buf[idx + 2] = UInt8(min(255, b * brightness))
                buf[idx + 3] = 255
                idx += 4
            }
        }
    }

    /// Exposed for tests: brightness at a pixel for a given surface.
    static func brightness(surface s: Surface, x: Double, y: Double) -> Double {
        let nx = -(2 * s.ax * x + s.bx)
        let ny = -(2 * s.ay * y + s.by)
        let dot = (nx * lightX + ny * lightY + lightZ) / (nx * nx + ny * ny + 1).squareRoot()
        return ambient + max(0, 0.85 * dot)
    }
}
