import SwiftUI

// MARK: - LockGlyph — hand-drawn closed/filled padlock (design `Icons.lock`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.lock` (24px viewBox) —
//   shackle       M6.48 8.64 A5.52 5.28 0 0 1 17.52 8.64   (stroke 2.64, fill none)
//   drop lines    M6.48 8.64 L6.48 11.04  M17.52 8.64 L17.52 11.04   (stroke 2.64)
//   body          <rect x=4.8 y=9.6 width=14.4 height=11.52 rx=2.64/>  (filled)
//
// 2026-08-25 redesign (rb-android-icon-parity): a CLOSED padlock (shackle connects to
// the body) — replaces the previous open-shackle stroke lock. Matches Android's
// `IconGlyphs.kt LockGlyph` (`RestrictionMaskView` / auth-gate semantics — "please log
// in" / "members only"). Replaces SF Symbol `lock.fill` at every lock call site
// (rb-ios-icon-parity).
//
// icons.jsx's shackle is STILL a raw SVG elliptical arc (rx=5.52 ry=5.28, chord ==
// 2·rx — the exact degenerate diametric case icon-authoring.md's rule 1 warns about).
// Per rb-ios-icon-parity design.md D-3, this is converted to 2 cubic-bezier quarter-
// ellipse segments (180°→270°→360°, shared `Path.addEllipticalArcSegmentBezier` — see
// `GlyphPathHelpers.swift`) rather than transcribed as a raw arc.
//
// Two draw styles (stroked shackle + drop lines, filled body) need two Path layers.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.fill` /
// `ZStack` / `.frame`).

/// The design's closed padlock glyph, hand-drawn to match `Icons.lock`. Replaces SF
/// Symbol `lock.fill` at the auth-gate badge and the restriction-mask overlay.
public struct LockGlyph: View {

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
            // Shackle (bezier-approximated ellipse arc) + 2 drop lines — stroked.
            Path { p in
                let center = CGPoint(x: 12 * s, y: 8.64 * s)
                let rx = 5.52 * s
                let ry = 5.28 * s
                // 9 o'clock → 12 o'clock → 3 o'clock (the short/upper way, matching the
                // source's large-arc=0 sweep=1 — see design.md D-3).
                p.addEllipticalArcSegmentBezier(center: center, rx: rx, ry: ry,
                                                 startDegrees: 180, endDegrees: 270)
                p.addEllipticalArcSegmentBezier(center: center, rx: rx, ry: ry,
                                                 startDegrees: 270, endDegrees: 360)

                // Drop lines — M6.48 8.64 L6.48 11.04 / M17.52 8.64 L17.52 11.04.
                p.move(to: CGPoint(x: 6.48 * s, y: 8.64 * s))
                p.addLine(to: CGPoint(x: 6.48 * s, y: 11.04 * s))
                p.move(to: CGPoint(x: 17.52 * s, y: 8.64 * s))
                p.addLine(to: CGPoint(x: 17.52 * s, y: 11.04 * s))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.64 * s, lineCap: .round, lineJoin: .round))

            // Body — filled rounded rect.
            Path { p in
                p.addRoundedRect(in: CGRect(x: 4.8 * s, y: 9.6 * s, width: 14.4 * s, height: 11.52 * s),
                                  cornerSize: CGSize(width: 2.64 * s, height: 2.64 * s))
            }
            .fill(color)
        }
        .frame(width: size, height: size)
    }
}
