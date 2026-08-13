import AppKit
import MacDirStatCore
import UniformTypeIdentifiers

/// Data source + delegate for the directory outline. Items are `FSNode`s.
/// Children are served lazily through a per-node sort cache so sorting never
/// touches more of the tree than the user has expanded.
@MainActor
final class OutlineCoordinator: NSObject {
    enum ColumnID: String, CaseIterable {
        case name, bar, percent, size, items, files, subdirs, modified

        var title: String {
            switch self {
            case .name: "Name"
            case .bar: "Subtree %"
            case .percent: "%"
            case .size: "Size"
            case .items: "Items"
            case .files: "Files"
            case .subdirs: "Folders"
            case .modified: "Last Change"
            }
        }

        var width: CGFloat {
            switch self {
            case .name: 260
            case .bar: 90
            case .percent: 46
            case .size: 76
            case .items: 66
            case .files: 66
            case .subdirs: 56
            case .modified: 118
            }
        }
    }

    weak var outlineView: NSOutlineView?
    var onSelect: (@MainActor (FSNode?) -> Void)?
    var onAction: (@MainActor (FSNode, FileAction) -> Void)?
    private(set) var root: FSNode?
    /// Last tree version the representable pushed; -1 forces initial load.
    var lastTreeVersion = -1
    private var isProgrammaticSelection = false

    private var sortColumn: ColumnID = .size
    private var sortAscending = false
    private var sortedChildren: [ObjectIdentifier: ContiguousArray<FSNode>] = [:]

    private var iconCache: [String: NSImage] = [:]

    // MARK: - Public API

    func setRoot(_ newRoot: FSNode?) {
        root = newRoot
        sortedChildren.removeAll()
        outlineView?.reloadData()
        if let newRoot {
            outlineView?.expandItem(newRoot)
        }
    }

    /// Expand ancestors and select `node` without echoing back into the model.
    func reveal(_ node: FSNode) {
        guard let outlineView else { return }
        isProgrammaticSelection = true
        defer { isProgrammaticSelection = false }
        for ancestor in node.ancestorChain.dropLast() {
            outlineView.expandItem(ancestor)
        }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    func selectedNode() -> FSNode? {
        guard let outlineView, outlineView.selectedRow >= 0 else { return nil }
        return outlineView.item(atRow: outlineView.selectedRow) as? FSNode
    }

    // MARK: - Sorting

    private func children(of node: FSNode) -> ContiguousArray<FSNode> {
        // Stored order is size-descending — the default sort is free.
        if sortColumn == .size || sortColumn == .bar || sortColumn == .percent {
            return sortAscending ? ContiguousArray(node.children.reversed()) : node.children
        }
        let key = ObjectIdentifier(node)
        if let cached = sortedChildren[key] { return cached }
        var sorted = node.children
        switch sortColumn {
        case .name:
            sorted.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .items:
            sorted.sort { $0.itemCount < $1.itemCount }
        case .files:
            sorted.sort { $0.fileCount < $1.fileCount }
        case .subdirs:
            sorted.sort { $0.subdirCount < $1.subdirCount }
        case .modified:
            sorted.sort { $0.modTime < $1.modTime }
        case .size, .bar, .percent:
            break
        }
        if !sortAscending { sorted.reverse() }
        sortedChildren[key] = sorted
        return sorted
    }

    // MARK: - Cells

    private func icon(for node: FSNode) -> NSImage {
        let key: String
        let type: UTType
        if node.isDirectory {
            key = node.flags.contains(.isPackage) ? ":package" : ":folder"
            type = node.flags.contains(.isPackage) ? .package : .folder
        } else if node.flags.contains(.isSymlink) {
            key = ":symlink"
            type = .aliasFile
        } else {
            let ext = node.fileExtension
            key = ext
            type = UTType(filenameExtension: ext) ?? .data
        }
        if let cached = iconCache[key] { return cached }
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: 16, height: 16)
        iconCache[key] = image
        return image
    }

    private func makeTextCell(identifier: NSUserInterfaceItemIdentifier, alignment: NSTextAlignment) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeNameCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(image)
        cell.addSubview(field)
        cell.imageView = image
        cell.textField = field
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

// MARK: - NSOutlineViewDataSource

extension OutlineCoordinator: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FSNode else { return root == nil ? 0 : 1 }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FSNode else { return root! }
        return children(of: node)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FSNode else { return false }
        return node.isDirectory && !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = outlineView.sortDescriptors.first,
              let key = descriptor.key, let column = ColumnID(rawValue: key) else { return }
        sortColumn = column
        sortAscending = descriptor.ascending
        sortedChildren.removeAll()
        let selected = selectedNode()
        outlineView.reloadData()
        if let selected {
            reveal(selected)
        }
    }
}

// MARK: - NSOutlineViewDelegate

extension OutlineCoordinator: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FSNode,
              let columnID = tableColumn.flatMap({ ColumnID(rawValue: $0.identifier.rawValue) })
        else { return nil }

        let parentSize = node.parent?.sizeOnDisk ?? node.sizeOnDisk
        let fraction = parentSize > 0 ? Double(node.sizeOnDisk) / Double(parentSize) : 0

        if columnID == .bar {
            let identifier = NSUserInterfaceItemIdentifier("bar")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? PercentBarCellView
                ?? {
                    let v = PercentBarCellView()
                    v.identifier = identifier
                    return v
                }()
            cell.fraction = fraction
            return cell
        }

        let identifier = NSUserInterfaceItemIdentifier(columnID.rawValue)
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = columnID == .name
                ? makeNameCell(identifier: identifier)
                : makeTextCell(identifier: identifier, alignment: columnID == .modified ? .left : .right)
        }

        let dimmed = node.flags.contains(.accessDenied) || node.flags.contains(.isOtherVolume)
        cell.textField?.textColor = dimmed ? .tertiaryLabelColor : (columnID == .name ? .labelColor : .secondaryLabelColor)

        switch columnID {
        case .name:
            var label = node.name
            if node.flags.contains(.accessDenied) { label += " 🔒" }
            if node.flags.contains(.isOtherVolume) { label += " (other volume)" }
            cell.textField?.stringValue = label
            cell.imageView?.image = icon(for: node)
        case .percent:
            cell.textField?.stringValue = Format.percent(fraction)
        case .size:
            cell.textField?.stringValue = Format.bytes(node.sizeOnDisk)
        case .items:
            cell.textField?.stringValue = node.isDirectory ? Format.count(node.itemCount) : ""
        case .files:
            cell.textField?.stringValue = node.isDirectory ? Format.count(Int(node.fileCount)) : ""
        case .subdirs:
            cell.textField?.stringValue = node.isDirectory ? Format.count(Int(node.subdirCount)) : ""
        case .modified:
            cell.textField?.stringValue = Format.date(node.modTime)
        case .bar:
            break
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isProgrammaticSelection else { return }
        onSelect?(selectedNode())
    }
}

// MARK: - Context menu

extension OutlineCoordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let outlineView, let node = clickedOrSelectedNode() else { return }
        _ = outlineView

        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealAction(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = node
        menu.addItem(reveal)

        let open = NSMenuItem(title: "Open", action: #selector(openAction(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = node
        menu.addItem(open)

        menu.addItem(.separator())

        let trash = NSMenuItem(title: "Move to Trash…", action: #selector(trashAction(_:)), keyEquivalent: "")
        trash.target = self
        trash.representedObject = node
        // Never offer to trash the scan root.
        trash.isEnabled = node.parent != nil
        menu.addItem(trash)
    }

    private func clickedOrSelectedNode() -> FSNode? {
        guard let outlineView else { return nil }
        if outlineView.clickedRow >= 0 {
            return outlineView.item(atRow: outlineView.clickedRow) as? FSNode
        }
        return selectedNode()
    }

    @objc private func revealAction(_ sender: NSMenuItem) {
        if let node = sender.representedObject as? FSNode { onAction?(node, .reveal) }
    }

    @objc private func openAction(_ sender: NSMenuItem) {
        if let node = sender.representedObject as? FSNode { onAction?(node, .open) }
    }

    @objc private func trashAction(_ sender: NSMenuItem) {
        if let node = sender.representedObject as? FSNode { onAction?(node, .moveToTrash) }
    }
}
