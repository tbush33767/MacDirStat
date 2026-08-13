import MacDirStatCore
import SwiftUI

/// Toolbar control shown while scanning: a stop glyph inside a ring that fills
/// to show scan progress. Clicking it stops the scan.
///
/// Progress is bytes-scanned ÷ the volume's used capacity — a real percentage
/// for disk scans. When the total is unknown (folder scans), the ring falls
/// back to an indeterminate spin.
struct ScanningStopButton: View {
    let progress: ScanProgress
    let totalBytes: Int64?
    let action: () -> Void

    @State private var spin = false

    // Ring and glyph share the stop button's own color (no accent blue).
    private var tint: Color { .secondary }

    var body: some View {
        Button(action: action) {
            // A hidden copy of the Refresh glyph fixes this button's intrinsic
            // size to exactly match it, so the toolbar never shifts when the
            // scan starts or stops. The ring draws in its place.
            Image(systemName: "arrow.clockwise")
                .hidden()
                .overlay {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        ring.padding(1)  // keep the stroke inside the glyph bounds
                    }
                }
        }
        .help("Stop the scan (⌘.)")
        .onAppear { spin = true }
    }

    @ViewBuilder
    private var ring: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 2)

            if let total = totalBytes, total > 0 {
                let fraction = min(1, max(0, Double(progress.snapshot.byteCount) / Double(total)))
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))  // start the fill at 12 o'clock
                    .animation(.easeOut(duration: 0.2), value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            }

            Image(systemName: "stop.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(tint)
        }
    }
}
