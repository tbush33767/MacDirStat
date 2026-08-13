import CoreGraphics
import Testing
@testable import MacDirStatCore

@Suite struct CushionMathTests {
    @Test func flatSurfaceBrightnessIsUniform() {
        let s = CushionRenderer.Surface()
        let b1 = CushionRenderer.brightness(surface: s, x: 10, y: 10)
        let b2 = CushionRenderer.brightness(surface: s, x: 200, y: 150)
        #expect(abs(b1 - b2) < 1e-9)
        #expect(b1 > 0 && b1 <= 1.0)
    }

    @Test func brightnessStaysInDisplayableRange() {
        var s = CushionRenderer.Surface()
        s.addXRidge(from: 0, to: 100, height: 0.75)
        s.addYRidge(from: 0, to: 100, height: 0.75)
        s.addXRidge(from: 20, to: 60, height: 0.56)
        s.addYRidge(from: 30, to: 70, height: 0.56)
        for x in stride(from: 0.5, to: 100, by: 3.7) {
            for y in stride(from: 0.5, to: 100, by: 3.7) {
                let b = CushionRenderer.brightness(surface: s, x: x, y: y)
                #expect(b >= 0 && b <= 1.2, "brightness \(b) at (\(x), \(y))")
            }
        }
    }

    @Test func ridgeCenterBrighterThanLowEdge() {
        // The light leans toward -x/-y, so with a single cushion the region
        // near the max-x/max-y corner faces away and must be darker than the
        // center. (WinDirStat's characteristic shading.)
        var s = CushionRenderer.Surface()
        s.addXRidge(from: 0, to: 100, height: 0.75)
        s.addYRidge(from: 0, to: 100, height: 0.75)
        let center = CushionRenderer.brightness(surface: s, x: 50, y: 50)
        let farCorner = CushionRenderer.brightness(surface: s, x: 99, y: 99)
        #expect(center > farCorner)
    }

    @Test func rendersImageOfRequestedSize() {
        let root = FSNode(name: "/tmp/x", parent: nil)
        root.flags.insert(.isDirectory)
        for i in 0..<4 {
            let f = FSNode(name: "f\(i).png", parent: root)
            f.sizeOnDisk = Int64(100 * (i + 1))
            root.children.append(f)
            root.sizeOnDisk += f.sizeOnDisk
        }
        root.children.sort { $0.sizeOnDisk > $1.sizeOnDisk }
        let size = CGSize(width: 64, height: 48)
        TreemapLayout.layout(root: root, in: CGRect(origin: .zero, size: size))
        let palette = Palette(extensionsBySize: ["png"])
        let image = CushionRenderer.render(root: root, size: size, palette: palette)
        #expect(image != nil)
        #expect(image?.width == 64)
        #expect(image?.height == 48)
    }
}
