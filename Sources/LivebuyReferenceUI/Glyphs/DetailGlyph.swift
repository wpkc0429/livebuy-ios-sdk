import SwiftUI

// MARK: - DetailGlyph — hand-drawn bulleted-list-in-a-box glyph (design `Icons.detail`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.detail` (24px viewBox, stroke 1.8, fill none
// for the frame + lines; filled dots) — a bordered rounded rect containing 3 rows of
// (small dot + line):
//   frame  <rect x=3 y=4 width=18 height=16 rx=3/>
//   row 1  <circle cx=7 cy=9  r=1/>  <path d="M10.5 9h7"/>
//   row 2  <circle cx=7 cy=12 r=1/>  <path d="M10.5 12h7"/>
//   row 3  <circle cx=7 cy=15 r=1/>  <path d="M10.5 15h7"/>
//
// 2026-08-25 redesign: replaces SF Symbol `doc.text` (a folded-corner document, not a
// bulleted list). Brand new shape — neither platform had this exact glyph before.
// Two draw styles in one icon (stroked frame/lines + filled dots) need two Path layers.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.fill` /
// `ZStack` / `.frame`).

/// The design's bulleted-list-in-a-box glyph, hand-drawn to match `Icons.detail`.
/// Replaces SF Symbol `doc.text` at the product-row detail button.
public struct DetailGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The stroke / dot-fill color (both share the same color, per the design).
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        ZStack {
            // Frame + 3 row lines — all stroked.
            Path { p in
                p.addRoundedRect(in: CGRect(x: 3 * s, y: 4 * s, width: 18 * s, height: 16 * s),
                                  cornerSize: CGSize(width: 3 * s, height: 3 * s))
                for rowY: CGFloat in [9, 12, 15] {
                    p.move(to: CGPoint(x: 10.5 * s, y: rowY * s))
                    p.addLine(to: CGPoint(x: 17.5 * s, y: rowY * s))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))

            // 3 bullet dots — filled.
            Path { p in
                let r = 1 * s
                for rowY: CGFloat in [9, 12, 15] {
                    p.addEllipse(in: CGRect(x: 7 * s - r, y: rowY * s - r, width: r * 2, height: r * 2))
                }
            }
            .fill(color)
        }
        .frame(width: size, height: size)
    }
}
