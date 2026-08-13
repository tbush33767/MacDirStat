import Foundation

/// Immutable snapshot handed from the scan thread to the main actor.
public struct ScanResult: Sendable {
    public let root: FSNode
    public let extensionStats: [ExtStat]
    public let palette: Palette
    public let wasCancelled: Bool
    public let duration: TimeInterval
    public let deniedCount: Int

    public init(
        root: FSNode,
        extensionStats: [ExtStat],
        palette: Palette,
        wasCancelled: Bool,
        duration: TimeInterval,
        deniedCount: Int
    ) {
        self.root = root
        self.extensionStats = extensionStats
        self.palette = palette
        self.wasCancelled = wasCancelled
        self.duration = duration
        self.deniedCount = deniedCount
    }
}
