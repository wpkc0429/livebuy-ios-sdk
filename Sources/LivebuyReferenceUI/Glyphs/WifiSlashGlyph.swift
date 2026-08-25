import SwiftUI

// MARK: - WifiSlashGlyph — hand-drawn struck-through wifi glyph (design `Icons.wifiSlash`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.wifiSlash` (24px viewBox) —
//   arc 1 (near)  M8.5 15.3 Q12 12 15.5 15.3    (stroke 1.8, quadratic — direct
//                                                 SwiftUI `addQuadCurve` mapping)
//   arc 2 (far)   M5 11.3 Q12 5.5 19 11.3        (stroke 1.8, quadratic)
//   dot           <circle cx=12 cy=19 r=1.3/>    (filled)
//   strike        M4 4 L20 20                    (stroke 2.2 — thicker override)
//
// 2026-08-25: one of 8 brand-new icons (no prior iOS/Android custom equivalent).
// Replaces SF Symbol `wifi.slash` at the stream-error icon badge (rb-ios-icon-parity).
// SVG `Q` (quadratic bezier) maps DIRECTLY to SwiftUI's `addQuadCurve` — no
// icon-authoring.md rule-1 arc conversion needed (that rule is for elliptical `a`/`A`
// commands, not quadratics).
//
// Three draw styles (thin-stroke arcs, filled dot, thick-stroke strike) need 3 Path
// layers.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.stroke` / `.fill` /
// `ZStack` / `.frame`).

/// The design's struck-through wifi glyph, hand-drawn to match `Icons.wifiSlash`.
/// Replaces SF Symbol `wifi.slash` at the stream-error icon badge.
public struct WifiSlashGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The stroke / fill color.
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        ZStack {
            // Two wifi arcs — thin stroke.
            Path { p in
                p.move(to: CGPoint(x: 8.5 * s, y: 15.3 * s))
                p.addQuadCurve(to: CGPoint(x: 15.5 * s, y: 15.3 * s),
                                control: CGPoint(x: 12 * s, y: 12 * s))
                p.move(to: CGPoint(x: 5 * s, y: 11.3 * s))
                p.addQuadCurve(to: CGPoint(x: 19 * s, y: 11.3 * s),
                                control: CGPoint(x: 12 * s, y: 5.5 * s))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))

            // Signal dot — filled.
            Path { p in
                let r = 1.3 * s
                p.addEllipse(in: CGRect(x: 12 * s - r, y: 19 * s - r, width: r * 2, height: r * 2))
            }
            .fill(color)

            // Strike-through diagonal — thicker stroke.
            Path { p in
                p.move(to: CGPoint(x: 4 * s, y: 4 * s))
                p.addLine(to: CGPoint(x: 20 * s, y: 20 * s))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}
