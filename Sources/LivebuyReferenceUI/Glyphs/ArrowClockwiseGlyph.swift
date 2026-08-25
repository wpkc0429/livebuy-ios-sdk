import SwiftUI

// MARK: - ArrowClockwiseGlyph — hand-drawn ~300° circular arc + arrowhead corner
//                               (design `Icons.arrowClockwise`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.arrowClockwise` (24px viewBox, stroke 2
// override, fill none) —
//   arc     M19 12 A7 7 0 1 1 15.5 6.2   (large-arc=1 sweep=1 — the LONG way around,
//                                          center (12,12) r=7, start (19,12) = 3 o'clock)
//   corner  M19 4.5 V9 H14.5              (arrowhead, near the arc's gap)
//
// 2026-08-25: one of 8 brand-new icons (no prior iOS/Android custom equivalent).
// Replaces SF Symbol `arrow.clockwise` at the retry CTA and the「換一批」reshuffle pill
// (rb-ios-icon-parity). icons.jsx's arc is STILL a raw SVG circular arc (rx==ry==7) —
// per design.md D-3, converted to 4 cubic-bezier ~90°-or-less segments (shared
// `Path.addEllipticalArcSegmentBezier`, see `GlyphPathHelpers.swift`) rather than
// transcribed as a raw arc. The end angle is DERIVED (via `atan2`) from the design's
// literal end point (15.5, 6.2), not a hand-typed magic-number degree value.
//
// One draw style (uniform stroke) — a single Path (arc subpath + corner subpath).
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.frame`).

/// The design's ~300° circular arc + arrowhead-corner glyph, hand-drawn to match
/// `Icons.arrowClockwise`. Replaces SF Symbol `arrow.clockwise` at the retry CTA and
/// the「換一批」reshuffle pill.
public struct ArrowClockwiseGlyph: View {

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
        let center = CGPoint(x: 12 * s, y: 12 * s)
        let r = 7 * s

        Path { p in
            // The arc's end point per icons.jsx (15.5, 6.2) — its angle (clockwise from
            // the positive x-axis, 0° = 3 o'clock) is DERIVED, not hand-typed, so the
            // sweep always matches the design's literal end point.
            let endPoint = CGPoint(x: 15.5 * s, y: 6.2 * s)
            let rawDegrees = Double(atan2(endPoint.y - center.y, endPoint.x - center.x)) * 180 / .pi
            let endDegrees = rawDegrees < 270 ? rawDegrees + 360 : rawDegrees

            // Sweep clockwise the LONG way (large-arc=1 sweep=1): 0°→90°→180°→270°→end.
            p.addEllipticalArcSegmentBezier(center: center, rx: r, ry: r, startDegrees: 0, endDegrees: 90)
            p.addEllipticalArcSegmentBezier(center: center, rx: r, ry: r, startDegrees: 90, endDegrees: 180)
            p.addEllipticalArcSegmentBezier(center: center, rx: r, ry: r, startDegrees: 180, endDegrees: 270)
            p.addEllipticalArcSegmentBezier(center: center, rx: r, ry: r, startDegrees: 270, endDegrees: endDegrees)

            // Arrowhead corner — M19 4.5 V9 H14.5.
            p.move(to: CGPoint(x: 19 * s, y: 4.5 * s))
            p.addLine(to: CGPoint(x: 19 * s, y: 9 * s))
            p.addLine(to: CGPoint(x: 14.5 * s, y: 9 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
