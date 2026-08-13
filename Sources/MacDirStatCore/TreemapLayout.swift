import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls/Huizing/van Wijk), applied per directory
/// as WinDirStat does: squarify a directory's children within its rect, then
/// recurse into each child directory's rect.
///
/// Writes `rect` into every node; nodes too small to draw get `.null`.
/// Runtime is bounded by pixel count thanks to the minimum-size cutoff.
public enum TreemapLayout {
    /// Rects smaller than this on either axis are not subdivided further.
    static let minSide: CGFloat = 3

    public static func layout(root: FSNode, in rect: CGRect) {
        clearRects(root)
        layoutNode(root, rect: rect)
    }

    private static func clearRects(_ node: FSNode) {
        node.rect = .null
        for child in node.children { clearRects(child) }
    }

    private static func layoutNode(_ node: FSNode, rect: CGRect) {
        node.rect = rect
        guard node.isDirectory, !node.children.isEmpty else { return }
        guard rect.width >= minSide, rect.height >= minSide, node.sizeOnDisk > 0 else { return }

        // Children are stored sorted by size descending (scan invariant).
        let visible = node.children.prefix { $0.sizeOnDisk > 0 }
        guard !visible.isEmpty else { return }
        squarify(children: Array(visible), rect: rect, totalSize: node.sizeOnDisk)
    }

    private static func squarify(children: [FSNode], rect: CGRect, totalSize: Int64) {
        var remaining = rect
        var index = 0
        let scale = Double(rect.width * rect.height) / Double(totalSize)

        while index < children.count {
            // The row is laid along the shorter side of the remaining rect.
            let shortSide = min(remaining.width, remaining.height)
            guard shortSide >= 1 else { break }

            // Greedily grow the row while the worst aspect ratio improves.
            var rowEnd = index + 1
            var rowArea = Double(children[index].sizeOnDisk) * scale
            var worst = worstAspect(rowArea: rowArea, maxArea: rowArea, minArea: rowArea, shortSide: Double(shortSide))
            var maxArea = rowArea
            var minArea = rowArea
            while rowEnd < children.count {
                let area = Double(children[rowEnd].sizeOnDisk) * scale
                if area <= 0 { break }
                let newMax = max(maxArea, area)
                let newMin = min(minArea, area)
                let newWorst = worstAspect(rowArea: rowArea + area, maxArea: newMax, minArea: newMin, shortSide: Double(shortSide))
                if newWorst > worst { break }
                rowArea += area
                maxArea = newMax
                minArea = newMin
                worst = newWorst
                rowEnd += 1
            }

            // Slice the row's strip off the remaining rect.
            let horizontal = remaining.width >= remaining.height
            let thickness = CGFloat(rowArea) / shortSide
            let strip: CGRect
            if horizontal {
                strip = CGRect(x: remaining.minX, y: remaining.minY, width: thickness, height: remaining.height)
                remaining.origin.x += thickness
                remaining.size.width -= thickness
            } else {
                strip = CGRect(x: remaining.minX, y: remaining.minY, width: remaining.width, height: thickness)
                remaining.origin.y += thickness
                remaining.size.height -= thickness
            }

            // Divide the strip among the row's members proportionally.
            var along = horizontal ? strip.minY : strip.minX
            for i in index..<rowEnd {
                let area = Double(children[i].sizeOnDisk) * scale
                let extent = rowArea > 0 ? CGFloat(area / rowArea) * shortSide : 0
                let childRect: CGRect
                if horizontal {
                    childRect = CGRect(x: strip.minX, y: along, width: strip.width, height: extent)
                } else {
                    childRect = CGRect(x: along, y: strip.minY, width: extent, height: strip.height)
                }
                along += extent
                if childRect.width >= 0.5, childRect.height >= 0.5 {
                    layoutNode(children[i], rect: childRect)
                }
            }
            index = rowEnd
        }
    }

    private static func worstAspect(rowArea: Double, maxArea: Double, minArea: Double, shortSide: Double) -> Double {
        // For a row of total area A laid across side s, member of area a gets
        // aspect ratio max((s²·a)/A², A²/(s²·a)).
        let s2 = shortSide * shortSide
        return max(s2 * maxArea / (rowArea * rowArea), rowArea * rowArea / (s2 * minArea))
    }
}
