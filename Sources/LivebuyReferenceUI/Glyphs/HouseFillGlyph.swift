import SwiftUI

// MARK: - HouseFillGlyph — hand-drawn filled house silhouette (design `Icons.houseFill`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.houseFill` (24px viewBox, filled) — single `d`:
//   M12 3 L3 10.5 V21 H9.5 V14.5 H14.5 V21 H21 V10.5 Z
//   (roof apex → left wall → base → door-notch cutout → right wall → close)
//
// 2026-08-25: one of 8 brand-new icons (no prior iOS/Android custom equivalent).
// Replaces SF Symbol `house.fill` at the VideoInfoPanel footer's「前往商城首頁」CTA
// (rb-ios-icon-parity). Straight lines only — direct transcription.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's filled house-silhouette glyph, hand-drawn to match `Icons.houseFill`.
/// Replaces SF Symbol `house.fill` at the VideoInfoPanel footer's「前往商城首頁」CTA.
public struct HouseFillGlyph: View {

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
            p.move(to: CGPoint(x: 12 * s, y: 3 * s))
            p.addLine(to: CGPoint(x: 3 * s, y: 10.5 * s))
            p.addLine(to: CGPoint(x: 3 * s, y: 21 * s))
            p.addLine(to: CGPoint(x: 9.5 * s, y: 21 * s))
            p.addLine(to: CGPoint(x: 9.5 * s, y: 14.5 * s))
            p.addLine(to: CGPoint(x: 14.5 * s, y: 14.5 * s))
            p.addLine(to: CGPoint(x: 14.5 * s, y: 21 * s))
            p.addLine(to: CGPoint(x: 21 * s, y: 21 * s))
            p.addLine(to: CGPoint(x: 21 * s, y: 10.5 * s))
            p.closeSubpath()
        }
        .fill(color)
        .frame(width: size, height: size)
    }
}
