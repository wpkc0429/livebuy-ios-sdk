import SwiftUI

// MARK: - PinFillGlyph — hand-drawn filled map-pin silhouette (design `Icons.pinFill`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.pinFill` (24px viewBox, filled) —
//   head  <circle cx=12 cy=7.5 r=4.5/>
//   tail  M10 11.5 L8 21 L12 18.5 L16 21 L14 11.5 Z   (straight-line polygon)
//
// 2026-08-25: one of 8 brand-new icons (no prior iOS/Android custom equivalent).
// Replaces SF Symbol `pin.fill` at the chat feed's pinned-message banner
// (rb-ios-icon-parity). Straight lines + a true circle — direct transcription, one
// fill style for both shapes → a single Path.
//
// Smallest actual render size in this codebase: 10pt
// (`ChatFeedView.PinnedMessageBanner`, its only call site) — visually confirmed
// legible at 10pt / 2x snapshot scale per icon-authoring.md rule 2 (see
// rb-ios-icon-parity tasks.md §8.4).
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's filled map-pin glyph, hand-drawn to match `Icons.pinFill`. Replaces SF
/// Symbol `pin.fill` at the chat feed's pinned-message banner.
public struct PinFillGlyph: View {

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
            let r = 4.5 * s
            p.addEllipse(in: CGRect(x: 12 * s - r, y: 7.5 * s - r, width: r * 2, height: r * 2))

            p.move(to: CGPoint(x: 10 * s, y: 11.5 * s))
            p.addLine(to: CGPoint(x: 8 * s, y: 21 * s))
            p.addLine(to: CGPoint(x: 12 * s, y: 18.5 * s))
            p.addLine(to: CGPoint(x: 16 * s, y: 21 * s))
            p.addLine(to: CGPoint(x: 14 * s, y: 11.5 * s))
            p.closeSubpath()
        }
        .fill(color)
        .frame(width: size, height: size)
    }
}
