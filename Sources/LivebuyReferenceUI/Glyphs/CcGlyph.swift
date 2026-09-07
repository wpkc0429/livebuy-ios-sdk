import SwiftUI

// MARK: - CcGlyph — hand-drawn closed-captions badge (design `Icons.cc`)
//
// Spec: `reference-ui-rendering/spec.md` (`rb-ios-cc-icon-design-align`, modifies the
// "LivebuyReferenceUI 渲染 OperationPanel 側欄 rail，綁 DefaultOperationRail" Requirement)
// Design: `design/shared/icons.jsx` `Icons.cc` (24px viewBox, stroke-only, fill none,
// strokeWidth 1.8, round cap/join — the shared `Icon` defaults) —
//
//   <rect x="3" y="5" width="18" height="14" rx="3" />
//   <path d="M9 11c-.5-.6-1.3-1-2-1-1.4 0-2.5 1.1-2.5 2.5S5.6 15 7 15c.7 0 1.5-.4 2-1
//            M16 11c-.5-.6-1.3-1-2-1-1.4 0-2.5 1.1-2.5 2.5S12.6 15 14 15c.7 0 1.5-.4 2-1" />
//
// The `path` is two independent subpaths — a "c" curve at x≈4.5–9 and its mirror at x≈11.5–16
// (each shifted +7 in x from the other) — every subpath command is a relative cubic (`c`) or a
// smooth-cubic shorthand (`S`, absolute). Expanding the `S` commands (reflecting the previous
// cubic's second control point about the current point, per the SVG spec) yields, for the first
// subpath (absolute, in the 24-box before `size/24` scaling):
//
//   M(9,11) C(8.5,10.4)(7.7,10)(7,10) C(5.6,10)(4.5,11.1)(4.5,12.5)
//           C(4.5,13.9)(5.6,15)(7,15) C(7.7,15)(8.5,14.6)(9,14)
//
// and the second subpath is the same shape shifted +7 in x (9→16, 7→14, 4.5→11.5, 5.6→12.6).
// This was verified against a standalone SVG-path-parser script (not hand-arithmetic only) and
// cross-checked against Android's `IconGlyphs.kt` `D_CC_CURVES` (`rb-android-icon-parity`),
// which carries the identical verbatim `icons.jsx` path string.
//
// Every SF Symbol equivalent (`captions.bubble`) draws a speech-bubble outline with "CC" text
// glyphs baked in — a different silhouette from the design's rounded badge + twin "c" curves.
// As with `ShareGlyph` / `ContactGlyph` / `PipGlyph`, we hand-draw it instead.
//
// Pure presentation: only `size` / `color`. The subtitle-toggle BEHAVIOR (onTapItem(.subtitle))
// is unchanged at the one call site (`OperationRailView.pillButton`).
//
// iOS-14-safe: `Path` / `.addRoundedRect(in:cornerSize:)` / `.stroke(_:style:)` / `.frame` are
// all iOS-13+ (same primitives `PipGlyph` already relies on).

/// The design's rounded-rect badge + twin hand-drawn "c" curves, matching `Icons.cc`. Replaces
/// SF Symbol `captions.bubble` at the VOD side-rail's `.subtitle` pill.
public struct CcGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The stroke color.
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        Path { p in
            // Outer badge — rounded rect, stroked (rx="3" → circular corner arcs, matching the
            // SVG's `rx`, not SwiftUI's default `.continuous` squircle style).
            p.addRoundedRect(in: CGRect(x: 3 * s, y: 5 * s, width: 18 * s, height: 14 * s),
                              cornerSize: CGSize(width: 3 * s, height: 3 * s),
                              style: .circular)

            // First "c" curve (left).
            p.move(to: CGPoint(x: 9 * s, y: 11 * s))
            p.addCurve(to: CGPoint(x: 7 * s, y: 10 * s),
                       control1: CGPoint(x: 8.5 * s, y: 10.4 * s), control2: CGPoint(x: 7.7 * s, y: 10 * s))
            p.addCurve(to: CGPoint(x: 4.5 * s, y: 12.5 * s),
                       control1: CGPoint(x: 5.6 * s, y: 10 * s), control2: CGPoint(x: 4.5 * s, y: 11.1 * s))
            p.addCurve(to: CGPoint(x: 7 * s, y: 15 * s),
                       control1: CGPoint(x: 4.5 * s, y: 13.9 * s), control2: CGPoint(x: 5.6 * s, y: 15 * s))
            p.addCurve(to: CGPoint(x: 9 * s, y: 14 * s),
                       control1: CGPoint(x: 7.7 * s, y: 15 * s), control2: CGPoint(x: 8.5 * s, y: 14.6 * s))

            // Second "c" curve (right) — the same shape, shifted +7 in x.
            p.move(to: CGPoint(x: 16 * s, y: 11 * s))
            p.addCurve(to: CGPoint(x: 14 * s, y: 10 * s),
                       control1: CGPoint(x: 15.5 * s, y: 10.4 * s), control2: CGPoint(x: 14.7 * s, y: 10 * s))
            p.addCurve(to: CGPoint(x: 11.5 * s, y: 12.5 * s),
                       control1: CGPoint(x: 12.6 * s, y: 10 * s), control2: CGPoint(x: 11.5 * s, y: 11.1 * s))
            p.addCurve(to: CGPoint(x: 14 * s, y: 15 * s),
                       control1: CGPoint(x: 11.5 * s, y: 13.9 * s), control2: CGPoint(x: 12.6 * s, y: 15 * s))
            p.addCurve(to: CGPoint(x: 16 * s, y: 14 * s),
                       control1: CGPoint(x: 14.7 * s, y: 15 * s), control2: CGPoint(x: 15.5 * s, y: 14.6 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
