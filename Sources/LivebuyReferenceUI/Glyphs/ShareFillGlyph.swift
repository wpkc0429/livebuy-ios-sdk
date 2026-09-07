import SwiftUI

// MARK: - ShareFillGlyph — hand-drawn FILLED share icon (design `Icons.shareFill`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-live-replay-more-menu-and-video-info-live-copy)
// Design: `design/shared/icons.jsx` `Icons.shareFill` — a FILLED variant of `Icons.share`
//   (24px viewBox, `stroke="none"`, `fill=currentColor`):
//
//   <circle cx="6"  cy="12" r="3" />
//   <circle cx="18" cy="6"  r="3" />
//   <circle cx="18" cy="18" r="3" />
//   <path d="M8.2 10.6l7.8-3.9 1 2-7.8 3.9zM8.2 13.4l7.8 3.9 1-2-7.8-3.9z" />
//
// Distinct from the existing STROKED `ShareGlyph` (`Icons.share`, used by the LIVE bottom
// bar's own share button / VideoInfoPanel elsewhere): this filled variant is what R32's new
// `LiveMoreSheetView`「分享」action slot uses (design `screens.jsx` `live_more` block —
// `<Icons.shareFill size={20} .../>`). Three filled r=3 nodes connected by two filled
// parallelogram bars (straight lines only, no arcs — direct transcription, no
// icon-authoring.md rule-1 conversion needed).
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's filled three-node share glyph, hand-drawn to match `Icons.shareFill`.
public struct ShareFillGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The fill color.
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        Path { p in
            // Three r=3 filled nodes at (6,12) / (18,6) / (18,18).
            for c in [(6.0, 12.0), (18.0, 6.0), (18.0, 18.0)] {
                let r = 3.0 * s
                p.addEllipse(in: CGRect(x: CGFloat(c.0) * s - r,
                                        y: CGFloat(c.1) * s - r,
                                        width: r * 2, height: r * 2))
            }
            // Connecting bar 1: M8.2 10.6 l7.8 -3.9 l1 2 l-7.8 3.9 z
            p.move(to: CGPoint(x: 8.2 * s, y: 10.6 * s))
            p.addLine(to: CGPoint(x: 16.0 * s, y: 6.7 * s))
            p.addLine(to: CGPoint(x: 17.0 * s, y: 8.7 * s))
            p.addLine(to: CGPoint(x: 9.2 * s, y: 12.6 * s))
            p.closeSubpath()
            // Connecting bar 2: M8.2 13.4 l7.8 3.9 l1 -2 l-7.8 -3.9 z
            p.move(to: CGPoint(x: 8.2 * s, y: 13.4 * s))
            p.addLine(to: CGPoint(x: 16.0 * s, y: 17.3 * s))
            p.addLine(to: CGPoint(x: 17.0 * s, y: 15.3 * s))
            p.addLine(to: CGPoint(x: 9.2 * s, y: 11.4 * s))
            p.closeSubpath()
        }
        .fill(color)
        .frame(width: size, height: size)
    }
}
