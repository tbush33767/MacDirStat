import Foundation

/// A mounted, user-visible volume — what the disk picker lists.
public struct VolumeInfo: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let totalCapacity: Int64
    /// Finder-style available space (accounts for purgeable storage) when the
    /// system provides it, plain available bytes otherwise.
    public let availableCapacity: Int64
    public let isRoot: Bool
    public let isInternal: Bool
    public let isReadOnly: Bool

    public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    public var usedFraction: Double {
        totalCapacity > 0 ? Double(usedCapacity) / Double(totalCapacity) : 0
    }

    /// All browsable mounted volumes, system disk first, largest first after.
    public static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
            .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable ?? false,
                  let total = values.volumeTotalCapacity, total > 0
            else { continue }
            let importantAvail = values.volumeAvailableCapacityForImportantUsage ?? 0
            let available = importantAvail > 0
                ? importantAvail
                : Int64(values.volumeAvailableCapacity ?? 0)
            volumes.append(
                VolumeInfo(
                    name: values.volumeName ?? url.lastPathComponent,
                    path: url.path,
                    totalCapacity: Int64(total),
                    availableCapacity: available,
                    isRoot: values.volumeIsRootFileSystem ?? (url.path == "/"),
                    isInternal: values.volumeIsInternal ?? false,
                    isReadOnly: values.volumeIsReadOnly ?? false
                ))
        }
        return volumes.sorted {
            if $0.isRoot != $1.isRoot { return $0.isRoot }
            return $0.totalCapacity > $1.totalCapacity
        }
    }

    /// Paths (relative to the volume root) that must not be scanned because
    /// their contents already appear elsewhere in the tree. On the system
    /// volume, `/System/Volumes/Data` is the raw mount of the Data volume
    /// whose contents are merged into `/` via firmlinks — scanning both
    /// double-counts the entire disk.
    public static func duplicateMounts(forVolumeAt path: String) -> [String] {
        guard path == "/" else { return [] }
        return ["System/Volumes/Data"]
    }
}
