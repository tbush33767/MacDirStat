import MacDirStatCore
import SwiftUI

/// WinDirStat's classic layout: directory tree and extension list on top,
/// treemap below, status strip at the bottom.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.result != nil {
                VSplitView {
                    HSplitView {
                        DirectoryOutlinePane()
                            .frame(minWidth: 360, idealWidth: 720, maxWidth: .infinity, maxHeight: .infinity)
                        ExtensionListPane()
                            .frame(minWidth: 240, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Ideal height tuned so the pane break lands between
                    // outline rows instead of slicing one.
                    .frame(minHeight: 180, idealHeight: 348)
                    // Hairline between the table panes and the treemap so
                    // scroll-clipped rows end against a border, not raw color.
                    VStack(spacing: 0) {
                        Divider()
                        TreemapPane()
                    }
                    .frame(minHeight: 200, maxHeight: .infinity)
                }
            } else if model.isScanning {
                scanningState
            } else {
                VolumePickerView()
            }
            Divider()
            ScanProgressBar()
        }
        .toolbar { toolbarContent }
        .navigationTitle(model.displayTitle)
        .navigationSubtitle(model.scannedURL?.path ?? "")
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Scanning \(model.displayTitle)…")
                .font(.title2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                ForEach(model.mountedVolumes) { volume in
                    Button {
                        model.startScan(volume: volume)
                    } label: {
                        Text("\(volume.name) — \(Format.bytes(volume.usedCapacity)) used")
                    }
                }
                Divider()
                Button("Choose Folder…") { model.openFolder() }
            } label: {
                Label("Scan", systemImage: "internaldrive")
            }
            .help("Scan a disk or folder (⌘O)")
            .disabled(model.isScanning)

            if let progress = model.scanProgress {
                ScanningStopButton(
                    progress: progress,
                    totalBytes: model.scannedVolume?.usedCapacity
                ) {
                    model.stopScan()
                }
            } else {
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Rescan the current folder (⌘R)")
                .disabled(model.scannedURL == nil)
            }

            Spacer()

            Button {
                model.performOnSelection(.reveal)
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }
            .help("Reveal the selected item in Finder (⇧⌘R)")
            .disabled(model.selectedNode == nil)

            Button {
                model.performOnSelection(.moveToTrash)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .help("Move the selected item to the Trash (⌘⌫)")
            .disabled(model.selectedNode == nil || model.selectedNode?.parent == nil)
        }
    }
}
