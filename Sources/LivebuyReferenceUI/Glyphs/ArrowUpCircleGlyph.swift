import SwiftUI

// MARK: - ArrowUpCircleGlyph — hand-drawn outline up-arrow-in-circle (design `Icons.arrowUpCircle`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.arrowUpCircle` (24px viewBox, stroke 2
// override, fill none) —
//   circle  <circle cx=12 cy=12 r=9/>
//   arrow   M12 16V8  M8 12L12 8L16 12   (vertical shaft + up-chevron head)
//
// 2026-08-25: one of 8 brand-new icons (no prior iOS/Android custom equivalent).
// Replaces SF Symbol `arrow.up.circle` at the outdated-build error icon badge
// (rb-ios-icon-parity). Straight lines + a true circle — no arc conversion needed
// (SwiftUI's `addEllipse` reproduces a full circle exactly, unlike icons.jsx's
// elliptical `A` commands elsewhere).
//
// One draw style (uniform stroke) — a single Path.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.frame`).

/// The design's outline up-arrow-in-circle glyph, hand-drawn to match
/// `Icons.arrowUpCircle`. Replaces SF Symbol `arrow.up.circle` at the outdated-build
/// error icon badge.
public struct ArrowUpCircleGlyph: View {

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
            let r = 9 * s
            p.addEllipse(in: CGRect(x: 12 * s - r, y: 12 * s - r, width: r * 2, height: r * 2))

            // Shaft — M12 16 V8.
            p.move(to: CGPoint(x: 12 * s, y: 16 * s))
            p.addLine(to: CGPoint(x: 12 * s, y: 8 * s))
            // Chevron head — M8 12 L12 8 L16 12.
            p.move(to: CGPoint(x: 8 * s, y: 12 * s))
            p.addLine(to: CGPoint(x: 12 * s, y: 8 * s))
            p.addLine(to: CGPoint(x: 16 * s, y: 12 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
