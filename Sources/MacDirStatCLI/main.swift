import Foundation
import MacDirStatCore
import Synchronization

// Test harness for the scan engine: scans a path, prints the top two levels
// with sizes, then totals + timing. Usage: macdirstat-cli <path>

guard CommandLine.arguments.count >= 2 else {
    print("usage: MacDirStatCLI <path>")
    exit(64)
}

let path = (CommandLine.arguments[1] as NSString).expandingTildeInPath
let progress = ScanProgress()

// Progress ticker on a background thread.
let ticker = Thread {
    while true {
        Thread.sleep(forTimeInterval: 1.0)
        let s = progress.snapshot
        FileHandle.standardError.write(
            Data("  … \(Format.count(s.itemCount)) items, \(Format.bytes(s.byteCount))\n".utf8))
    }
}
ticker.stackSize = 1 << 20
ticker.start()

// Scan on a dedicated thread with a deep stack (recursion depth == fs depth).
let resultBox = Mutex<ScanResult?>(nil)
let done = DispatchSemaphore(value: 0)
let excluding = VolumeInfo.duplicateMounts(forVolumeAt: (path as NSString).standardizingPath)
let scanThread = Thread {
    let r = ScanEngine.scan(path: path, progress: progress, excluding: excluding)
    resultBox.withLock { $0 = r }
    done.signal()
}
scanThread.stackSize = 16 << 20
scanThread.start()
done.wait()

guard let result = resultBox.withLock({ $0 }) else { exit(1) }
let root = result.root

func line(_ node: FSNode, indent: String) {
    let marker = node.isDirectory ? "/" : ""
    var suffix = ""
    if node.flags.contains(.accessDenied) { suffix = " [denied]" }
    if node.flags.contains(.isOtherVolume) { suffix = " [other volume]" }
    print("\(indent)\(Format.bytes(node.sizeOnDisk).padding(toLength: 12, withPad: " ", startingAt: 0)) \(node.name)\(marker)\(suffix)")
}

line(root, indent: "")
for child in root.children.prefix(15) {
    line(child, indent: "  ")
    if child.isDirectory {
        for grandchild in child.children.prefix(5) {
            line(grandchild, indent: "    ")
        }
        if child.children.count > 5 { print("      … \(child.children.count - 5) more") }
    }
}
if root.children.count > 15 { print("  … \(root.children.count - 15) more") }

print("""

total:      \(Format.bytes(root.sizeOnDisk)) on disk (\(Format.bytes(root.sizeLogical)) logical)
items:      \(Format.count(root.itemCount)) (\(Format.count(Int(root.fileCount))) files, \(Format.count(Int(root.subdirCount))) dirs)
denied:     \(result.deniedCount)
extensions: \(result.extensionStats.count)
elapsed:    \(String(format: "%.2f", result.duration))s (\(Format.count(Int(Double(root.itemCount) / max(result.duration, 0.001)))) items/s)
""")

for stat in result.extensionStats.prefix(10) {
    let name = stat.ext.isEmpty ? "<none>" : ".\(stat.ext)"
    print("  \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(Format.bytes(stat.bytes).padding(toLength: 12, withPad: " ", startingAt: 0)) \(Format.count(stat.fileCount)) files  \(Format.percent(stat.percent))")
}
exit(0)
