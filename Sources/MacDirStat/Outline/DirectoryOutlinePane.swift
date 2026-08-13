import AppKit
import MacDirStatCore
import SwiftUI

struct DirectoryOutlinePane: NSViewRepresentable {
    @Environment(AppModel.self) private var model

    func makeCoordinator() -> OutlineCoordinator {
        OutlineCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = NSOutlineView()
        outlineView.style = .inset
        outlineView.rowSizeStyle = .small
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsMultipleSelection = false
        outlineView.autosaveExpandedItems = false
        outlineView.autoresizesOutlineColumn = false

        for columnID in OutlineCoordinator.ColumnID.allCases {
            let column = NSTableColumn(identifier: .init(columnID.rawValue))
            column.title = columnID.title
            column.width = columnID.width
            column.minWidth = 40
            column.sortDescriptorPrototype = NSSortDescriptor(
                key: columnID.rawValue,
                ascending: columnID == .name || columnID == .modified
            )
            outlineView.addTableColumn(column)
            if columnID == .name {
                outlineView.outlineTableColumn = column
            }
        }

        let coordinator = context.coordinator
        coordinator.outlineView = outlineView
        outlineView.dataSource = coordinator
        outlineView.delegate = coordinator
        coordinator.onSelect = { node in
            model.select(node, source: .tree)
        }
        coordinator.onAction = { node, action in
            model.perform(action, on: node)
        }

        let menu = NSMenu()
        menu.delegate = coordinator
        outlineView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let root = model.result?.root

        if coordinator.root !== root || context.coordinator.lastTreeVersion != model.treeVersion {
            coordinator.lastTreeVersion = model.treeVersion
            coordinator.setRoot(root)
        }

        // Treemap clicks reveal in the tree; tree clicks must not echo.
        if model.selectionSource == .treemap,
           let node = model.selectedNode,
           coordinator.selectedNode() !== node {
            coordinator.reveal(node)
        }
    }
}
