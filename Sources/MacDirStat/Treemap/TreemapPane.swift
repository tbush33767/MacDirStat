import MacDirStatCore
import SwiftUI

struct TreemapPane: NSViewRepresentable {
    @Environment(AppModel.self) private var model

    func makeNSView(context: Context) -> TreemapNSView {
        let view = TreemapNSView(frame: .zero)
        view.onSelect = { node in
            model.select(node, source: .treemap)
        }
        return view
    }

    func updateNSView(_ view: TreemapNSView, context: Context) {
        view.configure(
            root: model.result?.root,
            palette: model.result?.palette,
            treeVersion: model.treeVersion
        )
        view.setHighlights(selected: model.selectedNode, ext: model.selectedExtension)
    }
}
