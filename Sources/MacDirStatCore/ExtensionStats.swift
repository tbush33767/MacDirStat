import Foundation

/// Aggregated statistics for one file extension across the scanned tree.
public struct ExtStat: Identifiable, Sendable, Equatable {
    public var id: String { ext }
    /// Lowercased extension without the dot; "" groups extension-less files.
    public let ext: String
    public let bytes: Int64
    public let fileCount: Int
    /// Fraction of the scan's total file bytes, 0...1.
    public let percent: Double
}

public enum ExtensionAggregator {
    /// Walks the tree once and returns per-extension totals, largest first.
    /// Duplicate hard links are excluded (their size was already counted).
    public static func aggregate(root: FSNode) -> [ExtStat] {
        var bytes: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        var stack: [FSNode] = [root]
        var totalBytes: Int64 = 0
        while let node = stack.popLast() {
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else {
                let ext = node.fileExtension
                bytes[ext, default: 0] += node.sizeOnDisk
                counts[ext, default: 0] += 1
                totalBytes += node.sizeOnDisk
            }
        }
        return bytes
            .map { ext, b in
                ExtStat(
                    ext: ext,
                    bytes: b,
                    fileCount: counts[ext] ?? 0,
                    percent: totalBytes > 0 ? Double(b) / Double(totalBytes) : 0
                )
            }
            .sorted { $0.bytes > $1.bytes }
    }
}
