import SwiftUI

// MARK: - HotFlameGlyph — hand-drawn FontAwesome-style flame silhouette
//                         (design `Icons.hot`, viewBox 0 0 448 512)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-product-row-number-badge)
// Design: `design/shared/icons.jsx` `Icons.hot` — a two-subpath fill (outer flame
//   silhouette + an inner notch that carves the "unlit" swoosh out via the SAME
//   nonzero-winding fill rule the browser's SVG default uses) — every segment is a
//   straight line or a cubic bezier, there is ONE relative `s` (smooth-cubic
//   shorthand) segment and NO elliptical `a`/`A` arc commands, so this glyph does
//   NOT need `icon-authoring.md` 規則 1's arc→bezier conversion — the coordinates
//   below are a DIRECT transcription of the design's own `d` path, expanded from
//   its relative/shorthand commands into absolute MoveTo / CurveTo / LineTo
//   segments (the `s` command's implicit first control point is the reflection of
//   the preceding curve's second control point about the current point, per the
//   SVG spec — worked out by hand once here rather than re-derived per platform).
//
// Non-square viewBox (448×512 — every OTHER hand-drawn glyph in this module is a
// 24×24 square, e.g. `EqualizerGlyph` / `CartFillGlyph`): scaled uniformly by
// `size / 512` (the LARGER dimension — 512 > 448 — is the limiting one) and
// horizontally centered, reproducing the browser SVG default
// `preserveAspectRatio="xMidYMid meet"` the design's shared `<Icon>` wrapper
// relies on (it never overrides `preserveAspectRatio`). Scaling both axes by
// `size / 448` instead would stretch the flame vertically past the `size × size`
// box the design's `<svg width={size} height={size}>` actually draws into.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's flame ("介紹中" HOT badge) glyph, hand-drawn to match `Icons.hot`
/// (FontAwesome "fire" glyph, viewBox `0 0 448 512`).
public struct HotFlameGlyph: View {

    /// The glyph box side length (pt). The flame is aspect-fit (scaled by the
    /// limiting 512 dimension) and horizontally centered inside a `size × size`
    /// square — see the file header's aspect-fit note.
    public let size: CGFloat

    /// The fill color.
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Self.flamePath(size: size)
            .fill(color)
            .frame(width: size, height: size)
    }

    /// Builds the flame `Path` at a given box size — extracted as a standalone, pure,
    /// unit-testable function (unit-test-discipline) so the hand-transcribed coordinates'
    /// endpoints / bounding box can be asserted without mounting SwiftUI (see design.md
    /// Risks: manual `s`-shorthand expansion carries hand-calculation risk).
    static func flamePath(size: CGFloat) -> Path {
        let scale = size / 512.0
        let dx = (size - 448 * scale) / 2
        // A `let`-bound closure, NOT a nested `func` — SwiftUI's implicit `@ViewBuilder`
        // transform of `body` (this used to be inlined there) rejects a closure containing
        // a local FUNCTION declaration ("closure containing a declaration cannot be used
        // with result builder 'ViewBuilder'"); kept as a closure here too for consistency,
        // though this function itself is no longer inside a `@ViewBuilder` context.
        let pt: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: x * scale + dx, y: y * scale) }

        return Path { p in
            // Outer flame silhouette — design `d`:
            //   M323.56 51.2 c-20.8 19.3-39.58 39.59-56.22 59.97
            //   C240.08 73.62 206.28 35.53 168 0 69.74 91.17 0 209.96 0 281.6
            //     0 408.85 100.29 512 224 512
            //   s224-103.15 224-230.4
            //   c0-53.27-51.98-163.14-124.44-230.4z
            // (the `s` segment's control1 (347.71,512) is the reflection of the
            // preceding curve's control2 (100.29,512) about the current point
            // (224,512): 2·224 − 100.29 = 347.71, 2·512 − 512 = 512.)
            p.move(to: pt(323.56, 51.2))
            p.addCurve(to: pt(267.34, 111.17), control1: pt(302.76, 70.5), control2: pt(283.98, 90.79))
            p.addCurve(to: pt(168, 0), control1: pt(240.08, 73.62), control2: pt(206.28, 35.53))
            p.addCurve(to: pt(0, 281.6), control1: pt(69.74, 91.17), control2: pt(0, 209.96))
            p.addCurve(to: pt(224, 512), control1: pt(0, 408.85), control2: pt(100.29, 512))
            p.addCurve(to: pt(448, 281.6), control1: pt(347.71, 512), control2: pt(448, 408.85))
            p.addCurve(to: pt(323.56, 51.2), control1: pt(448, 228.33), control2: pt(396.02, 118.46))
            p.closeSubpath()

            // Inner notch — design `d` (continues the same path):
            //   m-19.47 340.65
            //   C282.43 407.01 255.72 416 226.86 416 154.71 416 96 368.26 96 290.75
            //   c0-38.61 24.31-72.63 72.79-130.75 6.93 7.98 98.83 125.34 98.83 125.34
            //   l58.63-66.88
            //   c4.14 6.85 7.91 13.55 11.27 19.97 27.35 52.19 15.81 118.97-33.43 153.42z
            // Winding direction is preserved verbatim from the design (kept in the
            // SAME order the design authored it) — SwiftUI `.fill()`'s default
            // nonzero-winding rule needs the two subpaths' relative winding to stay
            // as authored for the notch to render as a hole, not a second solid area.
            p.move(to: pt(304.09, 391.85))
            p.addCurve(to: pt(226.86, 416), control1: pt(282.43, 407.01), control2: pt(255.72, 416))
            p.addCurve(to: pt(96, 290.75), control1: pt(154.71, 416), control2: pt(96, 368.26))
            p.addCurve(to: pt(168.79, 160), control1: pt(96, 252.14), control2: pt(120.31, 218.12))
            p.addCurve(to: pt(267.62, 285.34), control1: pt(175.72, 167.98), control2: pt(267.62, 285.34))
            p.addLine(to: pt(326.25, 218.46))
            p.addCurve(to: pt(337.52, 238.43), control1: pt(330.39, 225.31), control2: pt(334.16, 232.01))
            p.addCurve(to: pt(304.09, 391.85), control1: pt(364.87, 290.62), control2: pt(353.33, 357.4))
            p.closeSubpath()
        }
    }
}
