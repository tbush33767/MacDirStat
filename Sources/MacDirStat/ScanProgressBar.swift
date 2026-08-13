import MacDirStatCore
import SwiftUI

/// Status strip pinned under the treemap: live progress while scanning,
/// summary totals when done.
struct ScanProgressBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .idle:
                Text("Choose a folder to scan.")
                    .foregroundStyle(.secondary)

            case .scanning(let progress, let startedAt, _):
                ProgressView()
                    .controlSize(.small)
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let s = progress.snapshot
                    let elapsed = max(Date().timeIntervalSince(startedAt), 0.01)
                    let rate = Int(Double(s.itemCount) / elapsed)
                    HStack(spacing: 8) {
                        Text("\(Format.count(s.itemCount)) items · \(Format.bytes(s.byteCount)) · \(Format.count(rate))/s")
                            .monospacedDigit()
                        Text(s.currentPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()

            case .done(let result, let url):
                let root = result.root
                let name = model.scannedVolume?.name ?? url.path
                Text("\(name) — \(Format.bytes(root.sizeOnDisk)), \(Format.count(root.itemCount)) items (\(Format.count(Int(root.fileCount))) files, \(Format.count(Int(root.subdirCount))) folders) in \(String(format: "%.1f", result.duration))s")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let volume = model.scannedVolume {
                    Text("· \(Format.bytes(volume.availableCapacity)) free of \(Format.bytes(volume.totalCapacity))")
                        .foregroundStyle(.secondary)
                }
                if result.wasCancelled {
                    Text("(interrupted)")
                        .foregroundStyle(.orange)
                }
                if result.deniedCount > 0 {
                    Label("\(result.deniedCount) unreadable", systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .help("Some folders couldn't be read. Grant Full Disk Access in System Settings for a complete scan.")
                }
                Spacer()
            }
        }
        .font(.callout)
        // Side padding clears the window's rounded bottom corners (10 pt).
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
