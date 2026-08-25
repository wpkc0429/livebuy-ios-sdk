import SwiftUI

// MARK: - BagGlyph — hand-drawn FILL shopping-bag glyph (design `Icons.bag`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.bag` (24px viewBox) — local_mall.svg-style
// silhouette: a filled bag body with the handle drawn as a solid arch cut INTO the
// top edge, plus a hollow ring cutout in the lower body (peeking the handle loop
// through a hole via SVG nonzero fill-rule / 3 subpaths of opposing winding):
//
//   body   M17.44 9 L15.89 9 C15.89 6.85 14.15 5.11 12 5.11 C9.85 5.11 8.11 6.85 8.11 9
//          L6.56 9 C5.7 9 5.01 9.7 5.01 10.56 L5 19.89 C5 20.74 5.7 21.44 6.56 21.44
//          L17.44 21.44 C18.3 21.44 19 20.74 19 19.89 L19 10.56 C19 9.7 18.3 9 17.44 9 Z
//   handle hole   M12 6.67 C13.29 6.67 14.33 7.71 14.33 9 L9.67 9 C9.67 7.71 10.71 6.67 12 6.67 Z
//   ring hole     M12 14.44 C9.85 14.44 8.11 12.7 8.11 10.56 L10.4 10.56 C10.4 11.469
//                 11.114 12.2 12 12.2 C12.886 12.2 13.6 11.469 13.6 10.56 L15.89 10.56
//                 C15.89 12.7 14.15 14.44 12 14.44 Z
//
// 2026-08-25 redesign (rb-android-icon-parity, backfilled into icons.jsx): replaces the
// FLAT-TOP stroked silhouette that read like a trash can at small render sizes. This is
// a FILL shape, not stroke — the "hole" look comes from SwiftUI's default nonzero
// winding fill (matching SVG's default fill-rule), reproduced here by transcribing the
// 3 subpaths with the EXACT SAME winding direction as icons.jsx (no re-derivation).
//
// Replaces SF Symbol `bag` at every live call site (rb-ios-icon-parity).
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's filled shopping-bag glyph with a hollow ring cutout, hand-drawn to
/// match `Icons.bag`. Replaces SF Symbol `bag` at the floating bag button, the LIVE
/// bottom-bar bag button, and (design-scoped, not-yet-built on iOS) the purchase /
/// sale-card slots.
public struct BagGlyph: View {

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
            // Subpath 1 — outer silhouette (body + handle arch cut into the top edge).
            p.move(to: CGPoint(x: 17.44 * s, y: 9 * s))
            p.addLine(to: CGPoint(x: 15.89 * s, y: 9 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 5.11 * s),
                       control1: CGPoint(x: 15.89 * s, y: 6.85 * s),
                       control2: CGPoint(x: 14.15 * s, y: 5.11 * s))
            p.addCurve(to: CGPoint(x: 8.11 * s, y: 9 * s),
                       control1: CGPoint(x: 9.85 * s, y: 5.11 * s),
                       control2: CGPoint(x: 8.11 * s, y: 6.85 * s))
            p.addLine(to: CGPoint(x: 6.56 * s, y: 9 * s))
            p.addCurve(to: CGPoint(x: 5.01 * s, y: 10.56 * s),
                       control1: CGPoint(x: 5.7 * s, y: 9 * s),
                       control2: CGPoint(x: 5.01 * s, y: 9.7 * s))
            p.addLine(to: CGPoint(x: 5 * s, y: 19.89 * s))
            p.addCurve(to: CGPoint(x: 6.56 * s, y: 21.44 * s),
                       control1: CGPoint(x: 5 * s, y: 20.74 * s),
                       control2: CGPoint(x: 5.7 * s, y: 21.44 * s))
            p.addLine(to: CGPoint(x: 17.44 * s, y: 21.44 * s))
            p.addCurve(to: CGPoint(x: 19 * s, y: 19.89 * s),
                       control1: CGPoint(x: 18.3 * s, y: 21.44 * s),
                       control2: CGPoint(x: 19 * s, y: 20.74 * s))
            p.addLine(to: CGPoint(x: 19 * s, y: 10.56 * s))
            p.addCurve(to: CGPoint(x: 17.44 * s, y: 9 * s),
                       control1: CGPoint(x: 19 * s, y: 9.7 * s),
                       control2: CGPoint(x: 18.3 * s, y: 9 * s))
            p.closeSubpath()

            // Subpath 2 — handle inner hole (opposing winding → nonzero-fill cutout).
            p.move(to: CGPoint(x: 12 * s, y: 6.67 * s))
            p.addCurve(to: CGPoint(x: 14.33 * s, y: 9 * s),
                       control1: CGPoint(x: 13.29 * s, y: 6.67 * s),
                       control2: CGPoint(x: 14.33 * s, y: 7.71 * s))
            p.addLine(to: CGPoint(x: 9.67 * s, y: 9 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 6.67 * s),
                       control1: CGPoint(x: 9.67 * s, y: 7.71 * s),
                       control2: CGPoint(x: 10.71 * s, y: 6.67 * s))
            p.closeSubpath()

            // Subpath 3 — lower-body ring hole (the "hollow ring cutout" motif).
            p.move(to: CGPoint(x: 12 * s, y: 14.44 * s))
            p.addCurve(to: CGPoint(x: 8.11 * s, y: 10.56 * s),
                       control1: CGPoint(x: 9.85 * s, y: 14.44 * s),
                       control2: CGPoint(x: 8.11 * s, y: 12.7 * s))
            p.addLine(to: CGPoint(x: 10.4 * s, y: 10.56 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 12.2 * s),
                       control1: CGPoint(x: 10.4 * s, y: 11.469 * s),
                       control2: CGPoint(x: 11.114 * s, y: 12.2 * s))
            p.addCurve(to: CGPoint(x: 13.6 * s, y: 10.56 * s),
                       control1: CGPoint(x: 12.886 * s, y: 12.2 * s),
                       control2: CGPoint(x: 13.6 * s, y: 11.469 * s))
            p.addLine(to: CGPoint(x: 15.89 * s, y: 10.56 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 14.44 * s),
                       control1: CGPoint(x: 15.89 * s, y: 12.7 * s),
                       control2: CGPoint(x: 14.15 * s, y: 14.44 * s))
            p.closeSubpath()
        }
        // Default nonzero winding (SwiftUI `.fill` without `FillStyle(eoFill: true)`)
        // matches SVG's default fill-rule — the two inner subpaths render as holes
        // because they wind opposite the outer silhouette, exactly as authored.
        .fill(color)
        .frame(width: size, height: size)
    }
}
