import AppKit
import Foundation
import MacDirStatCore
import Observation
import os

let scanLog = Logger(subsystem: "com.tyler.MacDirStat", category: "scan")

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case idle
        case scanning(progress: ScanProgress, startedAt: Date, url: URL)
        case done(ScanResult, url: URL)
    }

    enum SelectionSource {
        case tree, treemap, none
    }

    var phase: Phase = .idle
    var selectedNode: FSNode?
    var selectionSource: SelectionSource = .none
    var selectedExtension: String?
    /// Bumped whenever tree contents change (rescan, prune) so AppKit-backed
    /// views know to reload.
    var treeVersion = 0
    /// Set when the current scan targets a whole volume (drives title and
    /// free-space display); nil for plain folder scans.
    var scannedVolume: VolumeInfo?

    var mountedVolumes: [VolumeInfo] { VolumeInfo.mounted() }

    var displayTitle: String {
        if let volume = scannedVolume { return volume.name }
        return scannedURL?.lastPathComponent ?? "MacDirStat"
    }

    var result: ScanResult? {
        if case .done(let result, _) = phase { return result }
        return nil
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var scanProgress: ScanProgress? {
        if case .scanning(let progress, _, _) = phase { return progress }
        return nil
    }

    var scannedURL: URL? {
        switch phase {
        case .idle: nil
        case .scanning(_, _, let url): url
        case .done(_, let url): url
        }
    }

    // MARK: - Scan lifecycle

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to scan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startScan(url: url)
    }

    func startScan(volume: VolumeInfo) {
        startScan(url: URL(fileURLWithPath: volume.path), volume: volume)
    }

    func startScan(url: URL, volume: VolumeInfo? = nil) {
        guard !isScanning else { return }
        guard FullDiskAccess.promptIfNeeded() == .proceed else { return }
        // A folder chosen inside a volume root still counts as a volume scan.
        scannedVolume = volume ?? mountedVolumes.first { $0.path == url.path }
        let progress = ScanProgress()
        phase = .scanning(progress: progress, startedAt: Date(), url: url)
        selectedNode = nil
        selectedExtension = nil
        selectionSource = .none

        let path = url.path
        let excluding = VolumeInfo.duplicateMounts(forVolumeAt: path)
        scanLog.info("scan starting: \(path, privacy: .public)")
        let thread = Thread {
            scanLog.info("scan thread running")
            let result = ScanEngine.scan(path: path, progress: progress, excluding: excluding)
            scanLog.info("scan returned: \(result.root.itemCount) items, cancelled=\(result.wasCancelled)")
            // Plain GCD handoff: an unstructured Task created from a bare
            // NSThread was observed (once) to never get scheduled, leaving the
            // UI stuck in .scanning forever. dispatch_async cannot be lost.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    scanLog.info("handoff running on main")
                    self.finishScan(result, url: url)
                }
            }
            scanLog.info("scan thread exiting")
        }
        // Deep stacks: scanner recursion depth equals filesystem depth.
        thread.stackSize = 16 << 20
        thread.name = "MacDirStat.scan"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func refresh() {
        guard let url = scannedURL, !isScanning else { return }
        startScan(url: url)
    }

    func stopScan() {
        if case .scanning(let progress, _, _) = phase {
            progress.cancel()
        }
    }

    private func finishScan(_ result: ScanResult, url: URL) {
        phase = .done(result, url: url)
        treeVersion += 1

        if result.root.flags.contains(.accessDenied), result.root.itemCount == 0 {
            presentRootDeniedAlert(path: url.path)
        }
    }

    // MARK: - Selection

    func select(_ node: FSNode?, source: SelectionSource) {
        selectedNode = node
        selectionSource = source
        if let node, !node.isDirectory {
            selectedExtension = node.fileExtension
        }
    }

    private func presentRootDeniedAlert(path: String) {
        let alert = NSAlert()
        alert.messageText = "Cannot read “\(path)”"
        alert.informativeText = """
        MacDirStat doesn't have permission to read this folder. For protected \
        locations, grant Full Disk Access in System Settings → Privacy & \
        Security, then rescan.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open System Settings")
        if alert.runModal() == .alertSecondButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
            NSWorkspace.shared.open(url)
        }
    }
}
