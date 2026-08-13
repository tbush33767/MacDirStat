import CoreGraphics
import Foundation

/// A node in the scanned file tree.
///
/// Thread-safety invariant (`@unchecked Sendable`): the tree is mutated only
/// (a) by the scan thread before the `ScanResult` handoff, and afterwards
/// (b) on the main actor (pruning after trash) or by the single active treemap
/// layout/render task (`rect`). Never mutate from two contexts concurrently.
///
/// Inherits `NSObject` so instances can serve directly as `NSOutlineView`
/// items (identity-based equality is exactly what we want there).
public final class FSNode: NSObject, @unchecked Sendable {
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let isDirectory = Flags(rawValue: 1 << 0)
        public static let isPackage = Flags(rawValue: 1 << 1)
        public static let accessDenied = Flags(rawValue: 1 << 2)
        public static let isSymlink = Flags(rawValue: 1 << 3)
        /// Hard link whose contents were already counted under another path.
        public static let isDuplicateHardLink = Flags(rawValue: 1 << 4)
        /// Mount point of a different volume; not traversed.
        public static let isOtherVolume = Flags(rawValue: 1 << 5)
    }

    public let name: String
    public unowned let parent: FSNode?
    public var children: ContiguousArray<FSNode> = []
    public var sizeOnDisk: Int64 = 0
    public var sizeLogical: Int64 = 0
    /// For directories: most recent modification time in the whole subtree.
    public var modTime: TimeInterval = 0
    public var fileCount: Int32 = 0
    public var subdirCount: Int32 = 0
    public var flags: Flags = []
    /// Treemap layout slot; `.null` when the node is too small to display.
    public var rect: CGRect = .null

    public init(name: String, parent: FSNode?) {
        self.name = name
        self.parent = parent
    }

    public var isDirectory: Bool { flags.contains(.isDirectory) }

    /// Lowercased filename extension, or "" for directories / no extension.
    public var fileExtension: String {
        guard !isDirectory else { return "" }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        let ext = name[name.index(after: dot)...]
        guard !ext.isEmpty, ext.count <= 12 else { return "" }
        return ext.lowercased()
    }

    /// Full path reconstructed by walking the parent chain. O(depth) — use
    /// only for the selected node, tooltips, and file actions, never in bulk.
    public var path: String {
        var components: [String] = []
        var node: FSNode? = self
        while let n = node {
            components.append(n.name)
            node = n.parent
        }
        // Root node's name is its absolute path.
        return components.reversed().joined(separator: "/")
            .replacingOccurrences(of: "//", with: "/")
    }

    public var url: URL { URL(fileURLWithPath: path) }

    /// Total number of items in the subtree (files + subdirs), self excluded.
    public var itemCount: Int { Int(fileCount) + Int(subdirCount) }

    /// Ancestor chain from the root down to (and including) self.
    public var ancestorChain: [FSNode] {
        var chain: [FSNode] = []
        var node: FSNode? = self
        while let n = node {
            chain.append(n)
            node = n.parent
        }
        return chain.reversed()
    }
}
