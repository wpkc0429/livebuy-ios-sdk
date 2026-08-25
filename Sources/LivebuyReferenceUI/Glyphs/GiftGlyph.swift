import SwiftUI

// MARK: - GiftGlyph — hand-drawn OUTLINE gift-box glyph (design `Icons.gift`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.gift` (24px viewBox, stroke 1.8 default,
// fill none) —
//   bow    M12 8.5L7.5 4.5L7.5 8.5Z  M12 8.5L16.5 4.5L16.5 8.5Z   (2 triangular loops)
//   lid    <rect x=4   y=8    width=16 height=3.5 rx=1/>
//   body   <rect x=5.5 y=11.5 width=13 height=8.5 rx=1.5/>
//
// 2026-08-25: one of 8 brand-new icons — a NEW outline variant, distinct from the
// pre-existing `Icons.giftFill` (filled, already backfilled into icons.jsx, still
// rendered via SF Symbol `gift.fill` at `WinClaimModalView.giftBadge` / `WinEntryView`
// — those call sites are UNCHANGED by this glyph). Replaces SF Symbol `gift` (the
// unfilled SF Symbol) at the win-claim modal's pending-product row
// (rb-ios-icon-parity). Straight lines only — direct transcription. One draw style
// (uniform stroke) — a single Path.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.frame`).

/// The design's outline gift-box glyph, hand-drawn to match `Icons.gift`. Replaces SF
/// Symbol `gift` (unfilled) at the win-claim modal's pending-product row. Distinct from
/// `Icons.giftFill` (`gift.fill` SF Symbol, unchanged elsewhere in this module).
public struct GiftGlyph: View {

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
            // Bow — 2 triangular loops.
            p.move(to: CGPoint(x: 12 * s, y: 8.5 * s))
            p.addLine(to: CGPoint(x: 7.5 * s, y: 4.5 * s))
            p.addLine(to: CGPoint(x: 7.5 * s, y: 8.5 * s))
            p.closeSubpath()
            p.move(to: CGPoint(x: 12 * s, y: 8.5 * s))
            p.addLine(to: CGPoint(x: 16.5 * s, y: 4.5 * s))
            p.addLine(to: CGPoint(x: 16.5 * s, y: 8.5 * s))
            p.closeSubpath()

            // Lid.
            p.addRoundedRect(in: CGRect(x: 4 * s, y: 8 * s, width: 16 * s, height: 3.5 * s),
                              cornerSize: CGSize(width: 1 * s, height: 1 * s))
            // Body.
            p.addRoundedRect(in: CGRect(x: 5.5 * s, y: 11.5 * s, width: 13 * s, height: 8.5 * s),
                              cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
