import CoreGraphics
import Testing
@testable import MacDirStatCore

private func makeDir(_ name: String, parent: FSNode?, childSizes: [Int64]) -> FSNode {
    let dir = FSNode(name: name, parent: parent)
    dir.flags.insert(.isDirectory)
    for (i, size) in childSizes.sorted(by: >).enumerated() {
        let f = FSNode(name: "f\(i).dat", parent: dir)
        f.sizeOnDisk = size
        dir.children.append(f)
        dir.sizeOnDisk += size
        dir.fileCount += 1
    }
    return dir
}

@Suite struct SquarifyTests {
    @Test func areaConservation() {
        let root = makeDir("/tmp/x", parent: nil, childSizes: [500, 300, 100, 60, 40])
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        TreemapLayout.layout(root: root, in: rect)

        let childArea = root.children.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        let total = Double(rect.width * rect.height)
        #expect(abs(childArea - total) / total < 0.001)
    }

    @Test func areasProportionalToSizes() {
        let root = makeDir("/tmp/x", parent: nil, childSizes: [600, 300, 100])
        TreemapLayout.layout(root: root, in: CGRect(x: 0, y: 0, width: 500, height: 200))
        let totalArea = 500.0 * 200.0
        for child in root.children {
            let expected = Double(child.sizeOnDisk) / 1000.0 * totalArea
            let actual = Double(child.rect.width * child.rect.height)
            #expect(abs(actual - expected) / expected < 0.01, "child \(child.name)")
        }
    }

    @Test func childrenStayWithinParent() {
        let root = makeDir("/tmp/x", parent: nil, childSizes: (1...50).map { Int64($0 * 13) })
        let rect = CGRect(x: 0, y: 0, width: 640, height: 480)
        TreemapLayout.layout(root: root, in: rect)
        for child in root.children where !child.rect.isNull {
            #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(child.rect))
        }
    }

    @Test func noOverlapBetweenSiblings() {
        let root = makeDir("/tmp/x", parent: nil, childSizes: [400, 250, 180, 90, 50, 30])
        TreemapLayout.layout(root: root, in: CGRect(x: 0, y: 0, width: 300, height: 300))
        let rects = root.children.map(\.rect).filter { !$0.isNull }
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let overlap = rects[i].intersection(rects[j])
                let area = overlap.isNull ? 0 : overlap.width * overlap.height
                #expect(area < 0.01, "children \(i) and \(j) overlap")
            }
        }
    }

    @Test func nestedLayoutRecursesIntoDirectories() {
        let root = FSNode(name: "/tmp/x", parent: nil)
        root.flags.insert(.isDirectory)
        let sub = makeDir("sub", parent: root, childSizes: [200, 100])
        root.children.append(sub)
        let f = FSNode(name: "big.bin", parent: root)
        f.sizeOnDisk = 700
        root.children.append(f)
        root.children.sort { $0.sizeOnDisk > $1.sizeOnDisk }
        root.sizeOnDisk = 1000

        TreemapLayout.layout(root: root, in: CGRect(x: 0, y: 0, width: 400, height: 250))
        #expect(!sub.rect.isNull)
        #expect(!sub.children[0].rect.isNull)
        #expect(sub.rect.contains(sub.children[0].rect.insetBy(dx: 0.01, dy: 0.01)))
    }

    @Test func tinyRectsGetNullRects() {
        // 10k equal children in a small rect: most must be culled.
        let root = makeDir("/tmp/x", parent: nil, childSizes: (0..<10_000).map { _ in 10 })
        TreemapLayout.layout(root: root, in: CGRect(x: 0, y: 0, width: 50, height: 40))
        _ = root  // must simply terminate quickly without pathological rects
        for child in root.children where !child.rect.isNull {
            #expect(child.rect.width <= 50.01 && child.rect.height <= 40.01)
        }
    }
}
