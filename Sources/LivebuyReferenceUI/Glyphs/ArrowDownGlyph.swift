import SwiftUI

// MARK: - ArrowDownGlyph — hand-drawn simple down arrow (design `Icons.arrowDown`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.arrowDown` (24px viewBox, stroke 1.8
// default, fill none) — single `d`:
//   M12 4V20M6 14L12 20L18 14   (vertical shaft + down-chevron head)
//
// 2026-08-25: one of 8 brand-new icons (no prior iOS/Android custom equivalent).
// Replaces SF Symbol `arrow.down` at the chat feed's「回到最新訊息」pill
// (rb-ios-icon-parity). Straight lines only — direct transcription.
//
// Smallest actual render size in this codebase: 10pt (`ChatFeedView.returnToLatestPill`,
// its only call site) — visually confirmed legible at 10pt / 2x snapshot scale per
// icon-authoring.md rule 2 (see rb-ios-icon-parity tasks.md §8.4).
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.frame`).

/// The design's simple down-arrow glyph, hand-drawn to match `Icons.arrowDown`.
/// Replaces SF Symbol `arrow.down` at the chat feed's「回到最新訊息」pill.
public struct ArrowDownGlyph: View {

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
            // Shaft — M12 4 V20.
            p.move(to: CGPoint(x: 12 * s, y: 4 * s))
            p.addLine(to: CGPoint(x: 12 * s, y: 20 * s))
            // Chevron head — M6 14 L12 20 L18 14.
            p.move(to: CGPoint(x: 6 * s, y: 14 * s))
            p.addLine(to: CGPoint(x: 12 * s, y: 20 * s))
            p.addLine(to: CGPoint(x: 18 * s, y: 14 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
