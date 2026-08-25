import SwiftUI

// MARK: - CartFillGlyph — hand-drawn cart-with-hook-handle-and-2-wheels silhouette
//                         (design `Icons.cartFill`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.cartFill` (24px viewBox) —
//   basket  <path d="M6 8L20 8L18 16L7 16Z" stroke="none"/>                (filled trapezoid)
//   handle  <path d="M3 5h2l1.6 3" fill="none" strokeWidth="2"/>            (stroked hook)
//   wheels  <circle cx=9 cy=20 r=1.6 stroke="none"/>
//           <circle cx=17 cy=20 r=1.6 stroke="none"/>                      (filled)
//
// 2026-08-25 redesign (rb-android-icon-parity): a SHARP-trapezoid basket body + hook
// handle + 2 wheels — replaces the previous rounded single-path outline that diverged
// from Android's actual `IconGlyphs.kt` `D_CART_FILL_BASKET` / `D_CART_FILL_HANDLE`
// render. Retires `ShopBagGlyph` at the 「查看購物車」CTA footer (rb-ios-icon-parity):
// the `bag` silhouette wasn't legible at the footer's small render size, and the design
// now specifies THIS glyph for that slot instead.
//
// Straight lines only (no arcs) — direct transcription. Two draw styles (filled
// basket+wheels, stroked handle) need two Path layers.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.fill` /
// `ZStack` / `.frame`).

/// The design's cart-with-hook-handle-and-2-wheels glyph, hand-drawn to match
/// `Icons.cartFill`. Replaces `ShopBagGlyph` at the product-list 「查看購物車」CTA footer.
public struct CartFillGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The fill / stroke color (both share the same color, per the design).
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        ZStack {
            // Basket body (sharp trapezoid) + 2 wheels — filled.
            Path { p in
                p.move(to: CGPoint(x: 6 * s, y: 8 * s))
                p.addLine(to: CGPoint(x: 20 * s, y: 8 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 16 * s))
                p.addLine(to: CGPoint(x: 7 * s, y: 16 * s))
                p.closeSubpath()

                let r = 1.6 * s
                for cx: CGFloat in [9, 17] {
                    p.addEllipse(in: CGRect(x: cx * s - r, y: 20 * s - r, width: r * 2, height: r * 2))
                }
            }
            .fill(color)

            // Hook handle — M3 5 h2 l1.6 3 → (3,5)→(5,5)→(6.6,8). Stroked, width 2.
            Path { p in
                p.move(to: CGPoint(x: 3 * s, y: 5 * s))
                p.addLine(to: CGPoint(x: 5 * s, y: 5 * s))
                p.addLine(to: CGPoint(x: 6.6 * s, y: 8 * s))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}
