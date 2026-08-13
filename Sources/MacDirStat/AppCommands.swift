import MacDirStatCore
import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { model.openFolder() }
                .keyboardShortcut("o")
                .disabled(model.isScanning)
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(model.scannedURL == nil || model.isScanning)
            Button("Stop Scan") { model.stopScan() }
                .keyboardShortcut(".")
                .disabled(!model.isScanning)
        }

        CommandMenu("Item") {
            Button("Reveal in Finder") { model.performOnSelection(.reveal) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedNode == nil)
            Button("Open") { model.performOnSelection(.open) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model.selectedNode == nil)
            Divider()
            Button("Move to Trash…") { model.performOnSelection(.moveToTrash) }
                .keyboardShortcut(.delete)
                .disabled(model.selectedNode == nil || model.selectedNode?.parent == nil)
        }
    }
}
