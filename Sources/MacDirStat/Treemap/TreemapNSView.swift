import AppKit
import MacDirStatCore

/// CGImage is immutable; safe to pass across the render-task boundary.
private struct ImageBox: @unchecked Sendable {
    let image: CGImage
}

/// The cushion-treemap view: a bitmap content layer rendered off the main
/// thread, plus shape layers for selection/extension highlights so selection
/// changes never trigger a re-render.
final class TreemapNSView: NSView, NSViewToolTipOwner {
    var onSelect: (@MainActor (FSNode) -> Void)?

    private let contentLayer = CALayer()
    private let selectionLayer = CAShapeLayer()
    private let extensionLayer = CAShapeLayer()

    private var root: FSNode?
    private var palette: Palette?
    private var treeVersion = -1
    private var selectedNode: FSNode?
    private var highlightedExtension: String?

    /// Size (points, 1x pixels) the current bitmap and node rects refer to.
    private var renderedSize: CGSize = .zero
    private var renderGeneration = 0
    private var debounceTask: Task<Void, Never>?
    /// Serializes layout+render so concurrent tasks never mutate `rect`.
    private static let renderQueue = DispatchQueue(label: "MacDirStat.treemap.render", qos: .userInitiated)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        contentLayer.magnificationFilter = .nearest
        contentLayer.anchorPoint = .zero
        selectionLayer.fillColor = nil
        selectionLayer.strokeColor = NSColor.white.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.shadowColor = NSColor.black.cgColor
        selectionLayer.shadowOpacity = 0.8
        selectionLayer.shadowRadius = 1.5
        selectionLayer.shadowOffset = .zero
        extensionLayer.fillColor = nil
        extensionLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        extensionLayer.lineWidth = 1
        layer?.addSublayer(contentLayer)
        layer?.addSublayer(extensionLayer)
        layer?.addSublayer(selectionLayer)
        addToolTip(bounds, owner: self, userData: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: - Inputs

    func configure(root: FSNode?, palette: Palette?, treeVersion: Int) {
        let changed = self.root !== root || self.treeVersion != treeVersion
        self.root = root
        self.palette = palette
        self.treeVersion = treeVersion
        if changed {
            scheduleRender(immediate: true)
        }
    }

    func setHighlights(selected: FSNode?, ext: String?) {
        selectedNode = selected
        highlightedExtension = ext
        updateOverlays()
    }

    // MARK: - Layout / rendering

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Stretch the stale bitmap while the re-render is pending.
        contentLayer.frame = bounds
        CATransaction.commit()
        removeAllToolTips()
        addToolTip(bounds, owner: self, userData: nil)
        scheduleRender(immediate: false)
        updateOverlays()
    }

    private func scheduleRender(immediate: Bool) {
        debounceTask?.cancel()
        let delay: Duration = immediate ? .zero : .milliseconds(100)
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.render()
        }
    }

    private func render() {
        guard let root, let palette else {
            contentLayer.contents = nil
            renderedSize = .zero
            updateOverlays()
            return
        }
        let size = CGSize(width: bounds.width.rounded(.down), height: bounds.height.rounded(.down))
        guard size.width >= 4, size.height >= 4 else { return }

        renderGeneration += 1
        let generation = renderGeneration

        Self.renderQueue.async { [weak self] in
            TreemapLayout.layout(root: root, in: CGRect(origin: .zero, size: size))
            guard let cgImage = CushionRenderer.render(root: root, size: size, palette: palette) else { return }
            let box = ImageBox(image: cgImage)
            Task { @MainActor in
                guard let self, generation == self.renderGeneration else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.contentLayer.contents = box.image
                self.contentLayer.frame = self.bounds
                CATransaction.commit()
                self.renderedSize = size
                self.updateOverlays()
            }
        }
    }

    // MARK: - Coordinate mapping

    /// View point → layout/bitmap coordinate space.
    private func layoutPoint(for viewPoint: CGPoint) -> CGPoint {
        guard renderedSize.width > 0, renderedSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return viewPoint }
        return CGPoint(
            x: viewPoint.x * renderedSize.width / bounds.width,
            y: viewPoint.y * renderedSize.height / bounds.height
        )
    }

    /// Layout rect → view coordinates (inverse of `layoutPoint`).
    private func viewRect(for layoutRect: CGRect) -> CGRect {
        guard renderedSize.width > 0, renderedSize.height > 0 else { return layoutRect }
        let sx = bounds.width / renderedSize.width
        let sy = bounds.height / renderedSize.height
        return CGRect(
            x: layoutRect.minX * sx, y: layoutRect.minY * sy,
            width: layoutRect.width * sx, height: layoutRect.height * sy
        )
    }

    func node(at viewPoint: CGPoint) -> FSNode? {
        guard let root, renderedSize != .zero else { return nil }
        let point = layoutPoint(for: viewPoint)
        guard !root.rect.isNull, root.rect.contains(point) else { return nil }
        var current = root
        descend: while current.isDirectory {
            for child in current.children where !child.rect.isNull && child.rect.contains(point) {
                current = child
                continue descend
            }
            break
        }
        return current
    }

    // MARK: - Overlays

    private func updateOverlays() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Selection frame: nearest ancestor that actually has a rect.
        if var node = selectedNode, root != nil, renderedSize != .zero {
            while node.rect.isNull, let parent = node.parent {
                node = parent
            }
            if node.rect.isNull {
                selectionLayer.path = nil
            } else {
                selectionLayer.path = CGPath(rect: viewRect(for: node.rect).insetBy(dx: 1, dy: 1), transform: nil)
            }
        } else {
            selectionLayer.path = nil
        }

        // Extension highlight: outline every visible leaf with that extension.
        if let ext = highlightedExtension, let root, renderedSize != .zero {
            let path = CGMutablePath()
            var count = 0
            collectExtensionRects(node: root, ext: ext, into: path, count: &count)
            extensionLayer.path = count > 0 ? path : nil
        } else {
            extensionLayer.path = nil
        }
    }

    private func collectExtensionRects(node: FSNode, ext: String, into path: CGMutablePath, count: inout Int) {
        guard !node.rect.isNull, count < 20_000 else { return }
        if node.isDirectory {
            for child in node.children {
                collectExtensionRects(node: child, ext: ext, into: path, count: &count)
            }
        } else if node.fileExtension == ext {
            path.addRect(viewRect(for: node.rect).insetBy(dx: 0.5, dy: 0.5))
            count += 1
        }
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = node(at: point) {
            onSelect?(hit)
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        guard let hit = node(at: point) else { return "" }
        return "\(hit.path)\n\(Format.bytes(hit.sizeOnDisk))"
    }
}
