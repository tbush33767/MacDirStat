import Foundation
import Testing
@testable import MacDirStatCore

/// Builds a fixture tree in a temp dir and verifies the scanner against
/// FileManager ground truth.
@Suite struct ScanEngineTests {
    func makeFixture() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MacDirStatTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        try fm.createDirectory(at: base.appendingPathComponent("sub1/nested"), withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("sub2"), withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("empty"), withIntermediateDirectories: true)

        try Data(repeating: 0xAB, count: 10_000).write(to: base.appendingPathComponent("a.bin"))
        try Data(repeating: 0xCD, count: 5_000).write(to: base.appendingPathComponent("sub1/b.txt"))
        try Data(repeating: 0xEF, count: 2_500).write(to: base.appendingPathComponent("sub1/nested/c.txt"))
        try Data(repeating: 0x01, count: 1_000).write(to: base.appendingPathComponent("sub2/d.log"))

        // Hard link: content must be counted once.
        try fm.linkItem(
            at: base.appendingPathComponent("a.bin"),
            to: base.appendingPathComponent("sub2/a-link.bin"))

        // Symlink to a directory: must not be followed.
        try fm.createSymbolicLink(
            at: base.appendingPathComponent("sub2/loop"),
            withDestinationURL: base)

        return base
    }

    @Test func scanMatchesGroundTruth() throws {
        let base = try makeFixture()
        defer { try? FileManager.default.removeItem(at: base) }

        let result = ScanEngine.scan(path: base.path, progress: ScanProgress())
        let root = result.root

        #expect(!result.wasCancelled)
        #expect(result.deniedCount == 0)

        // 4 files + 1 hardlink entry + 1 symlink + 4 dirs = 10 items.
        #expect(root.itemCount == 10)
        #expect(root.fileCount == 6)  // 5 regular entries + symlink leaf
        #expect(root.subdirCount == 4)

        // Logical size counts each file once (hard link deduplicated).
        #expect(root.sizeLogical >= 18_500)  // files + symlink target path bytes
        #expect(root.sizeLogical < 19_000)

        // Tree shape.
        let names = Set(root.children.map(\.name))
        #expect(names == ["sub1", "sub2", "empty", "a.bin"])
        let sub1 = root.children.first { $0.name == "sub1" }!
        #expect(sub1.isDirectory)
        #expect(sub1.sizeLogical >= 7_500)
        let nested = sub1.children.first { $0.name == "nested" }!
        #expect(nested.children.map(\.name) == ["c.txt"])

        // Symlink flagged and not followed (would loop forever otherwise).
        let sub2 = root.children.first { $0.name == "sub2" }!
        let loop = sub2.children.first { $0.name == "loop" }!
        #expect(loop.flags.contains(.isSymlink))
        #expect(!loop.isDirectory)

        // Hard link entry exists but contributes no size.
        let link = sub2.children.first { $0.name == "a-link.bin" }!
        let original = root.children.first { $0.name == "a.bin" }!
        #expect(link.flags.contains(.isDuplicateHardLink) != original.flags.contains(.isDuplicateHardLink))
        #expect(min(link.sizeLogical, original.sizeLogical) == 0)
        #expect(max(link.sizeLogical, original.sizeLogical) == 10_000)

        // Children sorted by size descending at every level.
        func checkSorted(_ node: FSNode) {
            let sizes = node.children.map(\.sizeOnDisk)
            #expect(sizes == sizes.sorted(by: >), "unsorted children in \(node.name)")
            node.children.forEach(checkSorted)
        }
        checkSorted(root)

        // Extension stats aggregate correctly (txt: 2 files, 7.5 KB logical).
        let txt = result.extensionStats.first { $0.ext == "txt" }
        #expect(txt?.fileCount == 2)

        // modTime propagated: root's subtree max >= each file's mtime.
        #expect(root.modTime > 0)
        #expect(root.modTime >= sub1.modTime)
    }

    @Test func exclusionsStubOutDuplicateMounts() throws {
        let base = try makeFixture()
        defer { try? FileManager.default.removeItem(at: base) }

        let result = ScanEngine.scan(
            path: base.path,
            progress: ScanProgress(),
            excluding: ["sub1/nested"]
        )
        let sub1 = result.root.children.first { $0.name == "sub1" }!
        let nested = sub1.children.first { $0.name == "nested" }!

        // Present but stubbed: no children, no size, flagged like a foreign mount.
        #expect(nested.flags.contains(.isOtherVolume))
        #expect(nested.children.isEmpty)
        #expect(nested.sizeLogical == 0)
        // sub1 contains only b.txt's bytes; c.txt was excluded.
        #expect(sub1.sizeLogical == 5_000)
        // Sibling dirs are unaffected.
        let sub2 = result.root.children.first { $0.name == "sub2" }!
        #expect(!sub2.children.isEmpty)
    }

    @Test func cancellationStopsEarly() throws {
        let base = try makeFixture()
        defer { try? FileManager.default.removeItem(at: base) }

        let progress = ScanProgress()
        progress.cancel()
        let result = ScanEngine.scan(path: base.path, progress: progress)
        #expect(result.wasCancelled)
    }

    @Test func nonexistentPathYieldsDeniedRoot() {
        let result = ScanEngine.scan(path: "/nonexistent-\(UUID().uuidString)", progress: ScanProgress())
        #expect(result.root.flags.contains(.accessDenied))
        #expect(result.root.itemCount == 0)
    }

    @Test func pathReconstruction() throws {
        let base = try makeFixture()
        defer { try? FileManager.default.removeItem(at: base) }

        let result = ScanEngine.scan(path: base.path, progress: ScanProgress())
        let sub1 = result.root.children.first { $0.name == "sub1" }!
        let nested = sub1.children.first { $0.name == "nested" }!
        let c = nested.children.first { $0.name == "c.txt" }!
        let expected = (base.path as NSString).standardizingPath + "/sub1/nested/c.txt"
        #expect(c.path == expected)
        #expect(FileManager.default.fileExists(atPath: c.path))
    }
}
