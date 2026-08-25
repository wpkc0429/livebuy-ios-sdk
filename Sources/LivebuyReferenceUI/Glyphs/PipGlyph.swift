import SwiftUI

// MARK: - PipGlyph — hand-drawn frame + inset rect + directional arrow (design `Icons.pip`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.pip` (24px viewBox) —
//   outer frame  <rect x=3  y=5  width=18 height=14 rx=2/>            (stroke, fill none)
//   inset rect   <rect x=11 y=11 width=8  height=6  rx=1/>            (filled, no stroke)
//   arrow        <path d="M7 8.5L9.6 11.1M9.6 8.5v2.6h-2.6"/>          (stroke, fill none)
//
// 2026-08-25 redesign: adds a directional (minimize) arrow onto the pre-existing
// frame+small-rect PiP-style motif — self-drawn (was SF Symbol `pip.enter`, which has
// no arrow). Replaces SF Symbol `pip.enter` at the player header's minimize button
// (rb-ios-icon-parity).
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.fill` /
// `ZStack` / `.frame`).

/// The design's frame + inset-rect + directional-arrow glyph, hand-drawn to match
/// `Icons.pip`. Replaces SF Symbol `pip.enter` at the player header minimize button.
public struct PipGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The stroke / fill color (both share the same color, per the design).
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        ZStack {
            // Outer frame + minimize-direction arrow — both stroked at the same width.
            Path { p in
                p.addRoundedRect(in: CGRect(x: 3 * s, y: 5 * s, width: 18 * s, height: 14 * s),
                                  cornerSize: CGSize(width: 2 * s, height: 2 * s))
                // Arrow diagonal — M7 8.5 L9.6 11.1.
                p.move(to: CGPoint(x: 7 * s, y: 8.5 * s))
                p.addLine(to: CGPoint(x: 9.6 * s, y: 11.1 * s))
                // Arrow corner — M9.6 8.5 v2.6 h-2.6 → (9.6,8.5)→(9.6,11.1)→(7,11.1).
                p.move(to: CGPoint(x: 9.6 * s, y: 8.5 * s))
                p.addLine(to: CGPoint(x: 9.6 * s, y: 11.1 * s))
                p.addLine(to: CGPoint(x: 7 * s, y: 11.1 * s))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))

            // Inset rect (the "screen" of the PiP frame) — filled.
            Path { p in
                p.addRoundedRect(in: CGRect(x: 11 * s, y: 11 * s, width: 8 * s, height: 6 * s),
                                  cornerSize: CGSize(width: 1 * s, height: 1 * s))
            }
            .fill(color)
        }
        .frame(width: size, height: size)
    }
}
