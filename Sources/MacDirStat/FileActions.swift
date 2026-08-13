import AppKit
import MacDirStatCore

enum FileAction {
    case reveal
    case open
    case moveToTrash
}

extension AppModel {
    func perform(_ action: FileAction, on node: FSNode) {
        switch action {
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        case .open:
            NSWorkspace.shared.open(node.url)
        case .moveToTrash:
            moveToTrash(node)
        }
    }

    func performOnSelection(_ action: FileAction) {
        guard let node = selectedNode else { return }
        perform(action, on: node)
    }

    // MARK: - Trash

    private func moveToTrash(_ node: FSNode) {
        guard node.parent != nil else { return }  // never trash the scan root

        let alert = NSAlert()
        alert.messageText = "Move “\(node.name)” to the Trash?"
        alert.informativeText = node.isDirectory
            ? "\(Format.count(node.itemCount)) items, \(Format.bytes(node.sizeOnDisk)). You can restore it from the Trash."
            : "\(Format.bytes(node.sizeOnDisk)). You can restore it from the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        NSWorkspace.shared.recycle([node.url]) { _, error in
            Task { @MainActor in
                if let error {
                    let failure = NSAlert()
                    failure.messageText = "Couldn't move “\(node.name)” to the Trash"
                    failure.informativeText = error.localizedDescription
                    failure.runModal()
                } else {
                    self.prune(node)
                }
            }
        }
    }

    /// Removes a trashed node from the in-memory tree, updating ancestor
    /// aggregates and extension stats — no rescan needed.
    private func prune(_ node: FSNode) {
        guard case .done(let result, let url) = phase,
              let parent = node.parent,
              let index = parent.children.firstIndex(where: { $0 === node })
        else { return }

        parent.children.remove(at: index)

        let removedFiles = node.isDirectory ? node.fileCount : 1
        let removedSubdirs = node.isDirectory ? node.subdirCount + 1 : 0
        var ancestor: FSNode? = parent
        while let current = ancestor {
            current.sizeOnDisk -= node.sizeOnDisk
            current.sizeLogical -= node.sizeLogical
            current.fileCount -= removedFiles
            current.subdirCount -= removedSubdirs
            ancestor = current.parent
        }

        if selectedNode === node || isDescendant(selectedNode, of: node) {
            selectedNode = nil
            selectionSource = .none
        }

        // Recompute extension totals (single fast walk); keep the original
        // palette so treemap colors stay stable.
        let stats = ExtensionAggregator.aggregate(root: result.root)
        phase = .done(
            ScanResult(
                root: result.root,
                extensionStats: stats,
                palette: result.palette,
                wasCancelled: result.wasCancelled,
                duration: result.duration,
                deniedCount: result.deniedCount
            ),
            url: url
        )
        treeVersion += 1
    }

    private func isDescendant(_ node: FSNode?, of ancestor: FSNode) -> Bool {
        var current = node?.parent
        while let c = current {
            if c === ancestor { return true }
            current = c.parent
        }
        return false
    }
}
