import SwiftUI

// MARK: - ArrowUpCircleFillGlyph — hand-drawn filled circle + white cutout arrow
//                                  (design `Icons.arrowUpCircleFill`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.arrowUpCircleFill` (24px viewBox) —
//   circle  <circle cx=12 cy=12 r=10/>                                   (filled, `color`)
//   arrow   M12 15.5V8.5  M8.3 12.2L12 8.5L15.7 12.2                     (stroke, FIXED
//           `#fff` — always white regardless of the circle's `color`, per icons.jsx)
//
// 2026-08-25: one of 8 brand-new icons (no prior iOS/Android custom equivalent).
// Replaces SF Symbol `arrow.up.circle.fill` at the chat composer's send button
// (rb-ios-icon-parity). The design HARD-CODES the inner arrow to white — the `color`
// param only tints the background disc (matches typical round send-button chrome: a
// tinted/dimmed disc with an always-legible white glyph on top).
//
// Two draw styles (filled disc in `color`, stroked arrow ALWAYS white) need 2 Path
// layers.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.fill` /
// `ZStack` / `.frame`).

/// The design's filled-circle + white-cutout-arrow glyph, hand-drawn to match
/// `Icons.arrowUpCircleFill`. Replaces SF Symbol `arrow.up.circle.fill` at the chat
/// composer send button. `color` tints ONLY the background disc — the arrow is always
/// white, per the design source.
public struct ArrowUpCircleFillGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The background-disc fill color. The arrow itself is always white (design-fixed).
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        ZStack {
            Path { p in
                let r = 10 * s
                p.addEllipse(in: CGRect(x: 12 * s - r, y: 12 * s - r, width: r * 2, height: r * 2))
            }
            .fill(color)

            Path { p in
                // Shaft — M12 15.5 V8.5.
                p.move(to: CGPoint(x: 12 * s, y: 15.5 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 8.5 * s))
                // Chevron head — M8.3 12.2 L12 8.5 L15.7 12.2.
                p.move(to: CGPoint(x: 8.3 * s, y: 12.2 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 8.5 * s))
                p.addLine(to: CGPoint(x: 15.7 * s, y: 12.2 * s))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}
