import AppKit
import MacDirStatCore
import SwiftUI

/// The start screen: WinDirStat's "Select Drives" dialog, macOS style —
/// mounted disks with usage bars, plus a folder-scan escape hatch.
struct VolumePickerView: View {
    @Environment(AppModel.self) private var model
    @State private var volumes: [VolumeInfo] = []

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)
            Text("Select a disk to scan")
                .font(.title2.weight(.semibold))

            VStack(spacing: 8) {
                ForEach(volumes) { volume in
                    VolumeRow(volume: volume) {
                        model.startScan(volume: volume)
                    }
                }
            }
            .frame(maxWidth: 480)

            Button("Select a Folder") { model.openFolder() }
                .controlSize(.regular)

            Spacer(minLength: 8)

            Label {
                Text("For a complete scan of the system disk, grant MacDirStat **Full Disk Access** in [Privacy & Security settings](x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles).")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { volumes = model.mountedVolumes }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWorkspace.didMountNotification)
                .merge(with: NotificationCenter.default.publisher(for: NSWorkspace.didUnmountNotification))
        ) { _ in
            volumes = model.mountedVolumes
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeInfo
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(volume.name)
                            .fontWeight(.medium)
                        if volume.isReadOnly {
                            Text("read-only")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Format.bytes(volume.usedCapacity)) of \(Format.bytes(volume.totalCapacity))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ProgressView(value: volume.usedFraction)
                        .progressViewStyle(.linear)
                        .tint(volume.usedFraction > 0.9 ? .orange : .accentColor)
                    Text("\(Format.bytes(volume.availableCapacity)) available")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: volume.path)
    }
}
