import SwiftUI

// MARK: - MoreGlyph — hand-drawn "更多" (⋯) glyph (design `Icons.more`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-live-replay-more-menu-and-video-info-live-copy)
// Design: `design/shared/icons.jsx` `Icons.more` — three r=1.4 FILLED circles at
//   (6,12) / (12,12) / (18,12) (24px viewBox, `stroke="none"`, `fill=currentColor`):
//
//   <circle cx="6" cy="12" r="1.4" /><circle cx="12" cy="12" r="1.4" /><circle cx="18" cy="12" r="1.4" />
//
// New for R32 — the LIVE bottom bar's replay (chat-closed) variant swaps its old CC-toggle
// slot for a "更多" button that opens `LiveMoreSheetView` (分享 + 客服). No existing SF Symbol
// approximates three equally-spaced dots at this exact proportion, so — matching every other
// hand-drawn glyph in this module (`ShareGlyph` / `MoreGlyph`'s own sibling `ContactGlyph`) —
// it is transcribed directly from `icons.jsx`.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's three-dot "更多" glyph, hand-drawn to match `Icons.more` (three filled
/// circles, evenly spaced on the horizontal center line).
public struct MoreGlyph: View {

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
            for cx in [6.0, 12.0, 18.0] {
                let r = 1.4 * s
                p.addEllipse(in: CGRect(x: CGFloat(cx) * s - r,
                                        y: 12 * s - r,
                                        width: r * 2, height: r * 2))
            }
        }
        .fill(color)
        .frame(width: size, height: size)
    }
}
