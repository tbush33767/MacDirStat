import AppKit

/// WinDirStat's "Subtree Percentage" bar: a filled bar showing this item's
/// share of its parent, drawn with the accent color.
final class PercentBarCellView: NSView {
    var fraction: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let barRect = bounds.insetBy(dx: 3, dy: 5)
        guard barRect.width > 2 else { return }

        let track = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        NSColor.quaternarySystemFill.setFill()
        track.fill()

        let clamped = max(0, min(1, fraction))
        guard clamped > 0 else { return }
        var fillRect = barRect
        fillRect.size.width = max(2, barRect.width * CGFloat(clamped))
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        NSColor.controlAccentColor.withAlphaComponent(0.8).setFill()
        fill.fill()
    }
}
