import Darwin
import Foundation

/// Recursive directory scanner built on `getattrlistbulk`, which returns
/// batches of directory entries with their attributes in a single syscall —
/// substantially faster than fts(3) or FileManager on APFS.
///
/// Rules:
/// - Symlinks are never followed (reported as leaf nodes).
/// - Hard-linked content is counted once (tracked by file ID).
/// - Volume boundaries are not crossed (mount points become stub nodes).
/// - Permission-denied directories are kept, flagged, and skipped.
///
/// Runs synchronously on the calling thread. Callers should provide a thread
/// with a generous stack (recursion depth == filesystem depth).
public enum ScanEngine {
    // Attribute bits, mirrored from <sys/attr.h>. Defined locally because the
    // C macros import into Swift with mixed signedness.
    private enum Attr {
        static let cmnReturnedAttrs: UInt32 = 0x8000_0000
        static let cmnError: UInt32 = 0x2000_0000
        static let cmnName: UInt32 = 0x0000_0001
        static let cmnObjType: UInt32 = 0x0000_0008
        static let cmnModTime: UInt32 = 0x0000_0400
        static let cmnFileID: UInt32 = 0x0200_0000
        static let fileLinkCount: UInt32 = 0x0000_0001
        static let fileTotalSize: UInt32 = 0x0000_0002
        static let fileAllocSize: UInt32 = 0x0000_0004
    }

    // fsobj_type_t values (vnode types).
    private static let VREG: UInt32 = 1
    private static let VDIR: UInt32 = 2
    private static let VLNK: UInt32 = 5

    private static let bufferSize = 128 * 1024

    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "appex", "kext", "plugin", "prefpane",
        "qlgenerator", "xcodeproj", "playground", "photoslibrary", "docset",
        "lproj", "scptd", "wdgt",
    ]

    private final class Context {
        let progress: ScanProgress
        var rootDev: dev_t = 0
        var seenHardLinks: Set<UInt64> = []
        var cancelled = false
        init(progress: ScanProgress) { self.progress = progress }
    }

    /// Scans `path` and returns the completed (or partial, if cancelled) result.
    /// `excluding` lists root-relative paths to stub out instead of descending
    /// into (used to skip duplicate mounts like `/System/Volumes/Data`).
    public static func scan(
        path: String,
        progress: ScanProgress,
        excluding: [String] = []
    ) -> ScanResult {
        let start = Date()
        let normalized = (path as NSString).standardizingPath
        let root = FSNode(name: normalized, parent: nil)
        root.flags.insert(.isDirectory)

        let exclusions = excluding.map { $0.split(separator: "/").map(String.init)[...] }
        let ctx = Context(progress: progress)
        let fd = open(normalized, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            root.flags.insert(.accessDenied)
            progress.recordDenied()
        } else {
            var st = stat()
            if fstat(fd, &st) == 0 { ctx.rootDev = st.st_dev }
            scanDirectory(node: root, fd: fd, ctx: ctx, exclusions: exclusions)
            close(fd)
        }

        let stats = ExtensionAggregator.aggregate(root: root)
        let palette = Palette(extensionsBySize: stats.map(\.ext))
        return ScanResult(
            root: root,
            extensionStats: stats,
            palette: palette,
            wasCancelled: ctx.cancelled,
            duration: Date().timeIntervalSince(start),
            deniedCount: progress.snapshot.deniedCount
        )
    }

    /// Enumerates the open directory `fd` into `node`, recursing into subdirs,
    /// then aggregates child stats bottom-up. Closes nothing; caller owns fd.
    /// `exclusions` holds the still-relevant excluded paths as remaining
    /// segments relative to this directory.
    private static func scanDirectory(
        node: FSNode,
        fd: Int32,
        ctx: Context,
        exclusions: [ArraySlice<String>] = []
    ) {
        ctx.progress.enteredDirectory(node.path)

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = Attr.cmnReturnedAttrs | Attr.cmnError | Attr.cmnName
            | Attr.cmnObjType | Attr.cmnModTime | Attr.cmnFileID
        attrs.fileattr = Attr.fileLinkCount | Attr.fileTotalSize | Attr.fileAllocSize

        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buf.deallocate() }

        batchLoop: while true {
            if ctx.cancelled || ctx.progress.isCancelled {
                ctx.cancelled = true
                break
            }
            let n = getattrlistbulk(fd, &attrs, buf, bufferSize, 0)
            if n <= 0 {
                // n == 0: done; n < 0: enumeration error — keep what we have.
                break
            }

            var batchItems = 0
            var batchBytes: Int64 = 0
            var offset = 0
            for _ in 0..<Int(n) {
                let entry = buf.advanced(by: offset)
                let entryLength = Int(entry.loadUnaligned(as: UInt32.self))
                if entryLength == 0 { break batchLoop }  // corrupt record; bail
                parseEntry(entry: entry, node: node, dirFD: fd, ctx: ctx,
                           exclusions: exclusions,
                           batchItems: &batchItems, batchBytes: &batchBytes)
                offset += entryLength
            }
            ctx.progress.add(items: batchItems, bytes: batchBytes)
        }

        // Bottom-up aggregation; children were fully scanned during recursion.
        for child in node.children {
            node.sizeOnDisk += child.sizeOnDisk
            node.sizeLogical += child.sizeLogical
            node.modTime = max(node.modTime, child.modTime)
            if child.isDirectory {
                node.subdirCount += 1 + child.subdirCount
                node.fileCount += child.fileCount
            } else {
                node.fileCount += 1
            }
        }
        node.children.sort { $0.sizeOnDisk > $1.sizeOnDisk }
    }

    /// Parses one variable-length getattrlistbulk record and adds the
    /// resulting child node (recursing immediately for subdirectories).
    private static func parseEntry(
        entry: UnsafeMutableRawPointer,
        node: FSNode,
        dirFD: Int32,
        ctx: Context,
        exclusions: [ArraySlice<String>],
        batchItems: inout Int,
        batchBytes: inout Int64
    ) {
        var offset = 4  // skip the u_int32 record length

        // ATTR_CMN_RETURNED_ATTRS is always first.
        let returned = entry.loadUnaligned(fromByteOffset: offset, as: attribute_set_t.self)
        offset += MemoryLayout<attribute_set_t>.size

        // ATTR_CMN_ERROR, when present, immediately follows RETURNED_ATTRS.
        var entryError: UInt32 = 0
        if returned.commonattr & Attr.cmnError != 0 {
            entryError = entry.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            offset += 4
        }

        var name = ""
        if returned.commonattr & Attr.cmnName != 0 {
            let refOffset = offset
            let ref = entry.loadUnaligned(fromByteOffset: offset, as: attrreference_t.self)
            let namePtr = entry.advanced(by: refOffset + Int(ref.attr_dataoffset))
            name = String(cString: namePtr.assumingMemoryBound(to: CChar.self))
            offset += MemoryLayout<attrreference_t>.size
        }

        var objType: UInt32 = 0
        if returned.commonattr & Attr.cmnObjType != 0 {
            objType = entry.loadUnaligned(fromByteOffset: offset, as: fsobj_type_t.self)
            offset += MemoryLayout<fsobj_type_t>.size
        }

        var modTime: TimeInterval = 0
        if returned.commonattr & Attr.cmnModTime != 0 {
            let ts = entry.loadUnaligned(fromByteOffset: offset, as: timespec.self)
            modTime = TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1e9
            offset += MemoryLayout<timespec>.size
        }

        var fileID: UInt64 = 0
        if returned.commonattr & Attr.cmnFileID != 0 {
            fileID = entry.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            offset += 8
        }

        var linkCount: UInt32 = 1
        if returned.fileattr & Attr.fileLinkCount != 0 {
            linkCount = entry.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            offset += 4
        }
        var totalSize: Int64 = 0
        if returned.fileattr & Attr.fileTotalSize != 0 {
            totalSize = entry.loadUnaligned(fromByteOffset: offset, as: Int64.self)
            offset += 8
        }
        var allocSize: Int64 = 0
        if returned.fileattr & Attr.fileAllocSize != 0 {
            allocSize = entry.loadUnaligned(fromByteOffset: offset, as: Int64.self)
            offset += 8
        }

        guard !name.isEmpty else { return }
        let child = FSNode(name: name, parent: node)
        child.modTime = modTime

        if entryError != 0 {
            child.flags.insert(.accessDenied)
            ctx.progress.recordDenied()
            node.children.append(child)
            batchItems += 1
            return
        }

        switch objType {
        case VDIR:
            child.flags.insert(.isDirectory)
            if packageExtensions.contains(nameExtension(of: name)) {
                child.flags.insert(.isPackage)
            }
            node.children.append(child)
            batchItems += 1

            // Excluded path (duplicate mount)? Stub it out like a foreign volume.
            var childExclusions: [ArraySlice<String>] = []
            for exclusion in exclusions where exclusion.first == name {
                if exclusion.count == 1 {
                    child.flags.insert(.isOtherVolume)
                    return
                }
                childExclusions.append(exclusion.dropFirst())
            }

            let childFD = openat(dirFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if childFD < 0 {
                if errno == EACCES || errno == EPERM {
                    child.flags.insert(.accessDenied)
                    ctx.progress.recordDenied()
                }
                return
            }
            defer { close(childFD) }
            // Don't descend into other volumes (mount points).
            var st = stat()
            if fstat(childFD, &st) == 0, st.st_dev != ctx.rootDev {
                child.flags.insert(.isOtherVolume)
                return
            }
            scanDirectory(node: child, fd: childFD, ctx: ctx, exclusions: childExclusions)
        case VREG:
            if linkCount > 1 {
                if ctx.seenHardLinks.contains(fileID) {
                    child.flags.insert(.isDuplicateHardLink)
                    totalSize = 0
                    allocSize = 0
                } else {
                    ctx.seenHardLinks.insert(fileID)
                }
            }
            child.sizeOnDisk = allocSize
            child.sizeLogical = totalSize
            node.children.append(child)
            batchItems += 1
            batchBytes += allocSize
        case VLNK:
            child.flags.insert(.isSymlink)
            child.sizeOnDisk = allocSize
            child.sizeLogical = totalSize
            node.children.append(child)
            batchItems += 1
        default:
            // Sockets, fifos, devices: ignore.
            return
        }
    }

    /// Extension check without needing an FSNode (directories use it for
    /// package detection before flags are final).
    private static func nameExtension(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}
