import SwiftUI
import CoreGraphics

// MARK: - GlyphPathHelpers — shared arc→bezier helper for hand-drawn glyphs
//
// Design: `design/contract/icon-authoring.md` 規則 1 (arc→cubic-bezier conversion).
//
// `LockGlyph`'s shackle and `ArrowClockwiseGlyph`'s main arc are still authored in
// `design/shared/icons.jsx` as raw SVG elliptical-arc commands (`A rx ry ...`).
// SwiftUI's `Path` has no direct elliptical-arc primitive (only a circular
// `addArc(center:radius:startAngle:endAngle:clockwise:)`), so this file provides a
// single shared, angle-based bezier approximation used by both glyphs — rather than
// each hand-deriving its own magic-number control points (rb-ios-icon-parity D-3).

extension Path {

    /// Appends ONE elliptical-arc segment, approximated as a cubic bezier, to the
    /// path — center/radii in the glyph's LOCAL (already-scaled) coordinate space,
    /// angles in DEGREES measured clockwise from the positive x-axis (0° = 3
    /// o'clock, 90° = 6 o'clock, 180° = 9 o'clock, 270° = 12 o'clock — screen/SVG
    /// convention, y grows downward).
    ///
    /// Valid for spans up to ~120° (the standard 4-bezier-per-circle tolerance);
    /// callers needing a larger sweep MUST split it into multiple segments (see
    /// `LockGlyph` / `ArrowClockwiseGlyph`).
    ///
    /// Moves to the segment's start point first UNLESS the path's current point
    /// already IS that point (lets callers chain consecutive segments without an
    /// extra `move(to:)` between them).
    mutating func addEllipticalArcSegmentBezier(
        center: CGPoint, rx: CGFloat, ry: CGFloat, startDegrees: Double, endDegrees: Double
    ) {
        let a0 = startDegrees * .pi / 180
        let a1 = endDegrees * .pi / 180
        let p0 = CGPoint(x: center.x + rx * CGFloat(cos(a0)), y: center.y + ry * CGFloat(sin(a0)))
        let p1 = CGPoint(x: center.x + rx * CGFloat(cos(a1)), y: center.y + ry * CGFloat(sin(a1)))

        // Bezier-arc control-point magnitude (per axis): k = (4/3)·tan(Δ/4).
        let k = CGFloat(4.0 / 3.0 * tan((a1 - a0) / 4))
        // Tangent direction (unit, pre-scale) at each endpoint: d/dθ (cosθ, sinθ) = (-sinθ, cosθ).
        let c0 = CGPoint(x: p0.x - rx * k * CGFloat(sin(a0)), y: p0.y + ry * k * CGFloat(cos(a0)))
        let c1 = CGPoint(x: p1.x + rx * k * CGFloat(sin(a1)), y: p1.y - ry * k * CGFloat(cos(a1)))

        if self.currentPoint != p0 {
            self.move(to: p0)
        }
        self.addCurve(to: p1, control1: c0, control2: c1)
    }
}
