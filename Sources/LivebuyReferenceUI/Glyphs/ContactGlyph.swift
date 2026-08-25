import SwiftUI

// MARK: - ContactGlyph — hand-drawn dual speech-bubble + question-mark glyph
//                        (design `Icons.contact`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-icon-parity)
// Design: `design/shared/icons.jsx` `Icons.contact` — single FILL path (24px viewBox,
// already affine-shifted y+2 from its original 24×20 authoring box into this repo's
// unified 24×24 viewBox; coordinates are pre-shifted, no further transform needed):
//
//   M22.4851 18.6388C23.4301 17.5213 24.0001 16.1225 24.0001 14.6C24.0001 10.955
//   20.7751 8 16.8001 8C16.7883 8 16.7769 8.0015 16.7651 8.0016C16.7813 8.1988
//   16.8001 8.3975 16.8001 8.6C16.8001 12.2983 13.8121 15.395 9.8213 16.1938
//   C10.6013 19.0662 13.3913 21.2 16.8001 21.2C18.0634 21.2 19.2496 20.8997
//   20.2819 20.3757C21.1951 20.825 22.3538 21.2 23.7113 21.2C23.826 21.2 23.9273
//   21.1353 23.9746 21.0273C24.0207 20.9193 23.9993 20.7968 23.9205 20.714
//   C23.9101 20.7013 23.0963 19.8238 22.4851 18.6388Z
//   M15.6001 8.6C15.6001 4.955 12.1088 2 7.8001 2C3.4913 2 0.0001 4.955 0.0001 8.6
//   C0.0001 10.0839 0.5858 11.4485 1.5627 12.5525C0.9481 13.781 0.0916 14.702
//   0.0781 14.7155C-0.0007 14.7982 -0.0221 14.9208 0.024 15.0288C0.0713 15.1363
//   0.1726 15.2 0.2873 15.2C1.7254 15.2 2.9408 14.783 3.8776 14.2985
//   C5.0326 14.8663 6.3676 15.2 7.8001 15.2C12.1088 15.2 15.6001 12.245 15.6001 8.6Z
//   M7.8188 12.8C7.3013 12.8 6.9001 12.3988 6.9001 11.8812C6.9001 11.3649
//   7.3017 10.9636 7.8177 10.9636C8.3341 10.9636 8.7353 11.3652 8.7353 11.8812
//   C8.7338 12.3988 8.3326 12.8 7.8188 12.8Z
//   M9.7913 8.4275L8.5051 9.23L8.5051 9.2873C8.5051 9.6601 8.1896 9.9755
//   7.817 9.9755C7.4443 9.9755 7.1288 9.6612 7.1288 9.29L7.1288 8.8287
//   C7.1288 8.5994 7.2435 8.3701 7.4729 8.2265L9.1075 7.2515
//   C9.3076 7.1375 9.4238 6.935 9.4238 6.7062C9.4238 6.3621 9.137 6.0755
//   8.7931 6.0755L7.3013 6.0755C6.9571 6.0755 6.6706 6.3622 6.6706 6.7062
//   C6.6706 7.079 6.3551 7.3944 5.9824 7.3944C5.6097 7.3944 5.2943 7.0789
//   5.2943 6.7062C5.2951 5.5891 6.1838 4.7 7.3013 4.7L8.7923 4.7
//   C9.9113 4.7 10.8001 5.5891 10.8001 6.7062C10.8001 7.3963 10.4288 8.0563
//   9.7913 8.4275Z
//
// 4 subpaths: the small (trailing, upper-right) speech bubble; the large (leading,
// lower-left) speech bubble; the question-mark's dot; the question-mark's hook stroke
// (all drawn as filled shapes — the design has no stroke elements here). Straight lines
// + cubic beziers only (no arcs) — direct transcription, no icon-authoring.md rule-1
// conversion needed.
//
// 2026-08-25 redesign: replaces SF Symbol `bubble.left.fill` at every 「聯繫商家」/
// service-link semantic slot (`OperationRailView` rail pill + `VideoInfoPanelView`
// footer's `message.fill` — both converge on this ONE glyph per rb-ios-icon-parity).
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's dual speech-bubble + question-mark glyph, hand-drawn to match
/// `Icons.contact`. Replaces SF Symbol `bubble.left.fill` (side-rail pill) and
/// `message.fill` (VideoInfoPanel footer) — both are the same 「聯繫商家」semantic.
public struct ContactGlyph: View {

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
            // Subpath 1 — small speech bubble (upper-right).
            p.move(to: CGPoint(x: 22.4851 * s, y: 18.6388 * s))
            p.addCurve(to: CGPoint(x: 24.0001 * s, y: 14.6 * s),
                       control1: CGPoint(x: 23.4301 * s, y: 17.5213 * s),
                       control2: CGPoint(x: 24.0001 * s, y: 16.1225 * s))
            p.addCurve(to: CGPoint(x: 16.8001 * s, y: 8 * s),
                       control1: CGPoint(x: 24.0001 * s, y: 10.955 * s),
                       control2: CGPoint(x: 20.7751 * s, y: 8 * s))
            p.addCurve(to: CGPoint(x: 16.7651 * s, y: 8.0016 * s),
                       control1: CGPoint(x: 16.7883 * s, y: 8 * s),
                       control2: CGPoint(x: 16.7769 * s, y: 8.0015 * s))
            p.addCurve(to: CGPoint(x: 16.8001 * s, y: 8.6 * s),
                       control1: CGPoint(x: 16.7813 * s, y: 8.1988 * s),
                       control2: CGPoint(x: 16.8001 * s, y: 8.3975 * s))
            p.addCurve(to: CGPoint(x: 9.8213 * s, y: 16.1938 * s),
                       control1: CGPoint(x: 16.8001 * s, y: 12.2983 * s),
                       control2: CGPoint(x: 13.8121 * s, y: 15.395 * s))
            p.addCurve(to: CGPoint(x: 16.8001 * s, y: 21.2 * s),
                       control1: CGPoint(x: 10.6013 * s, y: 19.0662 * s),
                       control2: CGPoint(x: 13.3913 * s, y: 21.2 * s))
            p.addCurve(to: CGPoint(x: 20.2819 * s, y: 20.3757 * s),
                       control1: CGPoint(x: 18.0634 * s, y: 21.2 * s),
                       control2: CGPoint(x: 19.2496 * s, y: 20.8997 * s))
            p.addCurve(to: CGPoint(x: 23.7113 * s, y: 21.2 * s),
                       control1: CGPoint(x: 21.1951 * s, y: 20.825 * s),
                       control2: CGPoint(x: 22.3538 * s, y: 21.2 * s))
            p.addCurve(to: CGPoint(x: 23.9746 * s, y: 21.0273 * s),
                       control1: CGPoint(x: 23.826 * s, y: 21.2 * s),
                       control2: CGPoint(x: 23.9273 * s, y: 21.1353 * s))
            p.addCurve(to: CGPoint(x: 23.9205 * s, y: 20.714 * s),
                       control1: CGPoint(x: 24.0207 * s, y: 20.9193 * s),
                       control2: CGPoint(x: 23.9993 * s, y: 20.7968 * s))
            p.addCurve(to: CGPoint(x: 22.4851 * s, y: 18.6388 * s),
                       control1: CGPoint(x: 23.9101 * s, y: 20.7013 * s),
                       control2: CGPoint(x: 23.0963 * s, y: 19.8238 * s))
            p.closeSubpath()

            // Subpath 2 — large speech bubble (leading, lower-left).
            p.move(to: CGPoint(x: 15.6001 * s, y: 8.6 * s))
            p.addCurve(to: CGPoint(x: 7.8001 * s, y: 2 * s),
                       control1: CGPoint(x: 15.6001 * s, y: 4.955 * s),
                       control2: CGPoint(x: 12.1088 * s, y: 2 * s))
            p.addCurve(to: CGPoint(x: 0.0001 * s, y: 8.6 * s),
                       control1: CGPoint(x: 3.4913 * s, y: 2 * s),
                       control2: CGPoint(x: 0.0001 * s, y: 4.955 * s))
            p.addCurve(to: CGPoint(x: 1.5627 * s, y: 12.5525 * s),
                       control1: CGPoint(x: 0.0001 * s, y: 10.0839 * s),
                       control2: CGPoint(x: 0.5858 * s, y: 11.4485 * s))
            p.addCurve(to: CGPoint(x: 0.0781 * s, y: 14.7155 * s),
                       control1: CGPoint(x: 0.9481 * s, y: 13.781 * s),
                       control2: CGPoint(x: 0.0916 * s, y: 14.702 * s))
            p.addCurve(to: CGPoint(x: 0.024 * s, y: 15.0288 * s),
                       control1: CGPoint(x: -0.0007 * s, y: 14.7982 * s),
                       control2: CGPoint(x: -0.0221 * s, y: 14.9208 * s))
            p.addCurve(to: CGPoint(x: 0.2873 * s, y: 15.2 * s),
                       control1: CGPoint(x: 0.0713 * s, y: 15.1363 * s),
                       control2: CGPoint(x: 0.1726 * s, y: 15.2 * s))
            p.addCurve(to: CGPoint(x: 3.8776 * s, y: 14.2985 * s),
                       control1: CGPoint(x: 1.7254 * s, y: 15.2 * s),
                       control2: CGPoint(x: 2.9408 * s, y: 14.783 * s))
            p.addCurve(to: CGPoint(x: 7.8001 * s, y: 15.2 * s),
                       control1: CGPoint(x: 5.0326 * s, y: 14.8663 * s),
                       control2: CGPoint(x: 6.3676 * s, y: 15.2 * s))
            p.addCurve(to: CGPoint(x: 15.6001 * s, y: 8.6 * s),
                       control1: CGPoint(x: 12.1088 * s, y: 15.2 * s),
                       control2: CGPoint(x: 15.6001 * s, y: 12.245 * s))
            p.closeSubpath()

            // Subpath 3 — question-mark dot.
            p.move(to: CGPoint(x: 7.8188 * s, y: 12.8 * s))
            p.addCurve(to: CGPoint(x: 6.9001 * s, y: 11.8812 * s),
                       control1: CGPoint(x: 7.3013 * s, y: 12.8 * s),
                       control2: CGPoint(x: 6.9001 * s, y: 12.3988 * s))
            p.addCurve(to: CGPoint(x: 7.8177 * s, y: 10.9636 * s),
                       control1: CGPoint(x: 6.9001 * s, y: 11.3649 * s),
                       control2: CGPoint(x: 7.3017 * s, y: 10.9636 * s))
            p.addCurve(to: CGPoint(x: 8.7353 * s, y: 11.8812 * s),
                       control1: CGPoint(x: 8.3341 * s, y: 10.9636 * s),
                       control2: CGPoint(x: 8.7353 * s, y: 11.3652 * s))
            p.addCurve(to: CGPoint(x: 7.8188 * s, y: 12.8 * s),
                       control1: CGPoint(x: 8.7338 * s, y: 12.3988 * s),
                       control2: CGPoint(x: 8.3326 * s, y: 12.8 * s))
            p.closeSubpath()

            // Subpath 4 — question-mark hook.
            p.move(to: CGPoint(x: 9.7913 * s, y: 8.4275 * s))
            p.addLine(to: CGPoint(x: 8.5051 * s, y: 9.23 * s))
            p.addLine(to: CGPoint(x: 8.5051 * s, y: 9.2873 * s))
            p.addCurve(to: CGPoint(x: 7.817 * s, y: 9.9755 * s),
                       control1: CGPoint(x: 8.5051 * s, y: 9.6601 * s),
                       control2: CGPoint(x: 8.1896 * s, y: 9.9755 * s))
            p.addCurve(to: CGPoint(x: 7.1288 * s, y: 9.29 * s),
                       control1: CGPoint(x: 7.4443 * s, y: 9.9755 * s),
                       control2: CGPoint(x: 7.1288 * s, y: 9.6612 * s))
            p.addLine(to: CGPoint(x: 7.1288 * s, y: 8.8287 * s))
            p.addCurve(to: CGPoint(x: 7.4729 * s, y: 8.2265 * s),
                       control1: CGPoint(x: 7.1288 * s, y: 8.5994 * s),
                       control2: CGPoint(x: 7.2435 * s, y: 8.3701 * s))
            p.addLine(to: CGPoint(x: 9.1075 * s, y: 7.2515 * s))
            p.addCurve(to: CGPoint(x: 9.4238 * s, y: 6.7062 * s),
                       control1: CGPoint(x: 9.3076 * s, y: 7.1375 * s),
                       control2: CGPoint(x: 9.4238 * s, y: 6.935 * s))
            p.addCurve(to: CGPoint(x: 8.7931 * s, y: 6.0755 * s),
                       control1: CGPoint(x: 9.4238 * s, y: 6.3621 * s),
                       control2: CGPoint(x: 9.137 * s, y: 6.0755 * s))
            p.addLine(to: CGPoint(x: 7.3013 * s, y: 6.0755 * s))
            p.addCurve(to: CGPoint(x: 6.6706 * s, y: 6.7062 * s),
                       control1: CGPoint(x: 6.9571 * s, y: 6.0755 * s),
                       control2: CGPoint(x: 6.6706 * s, y: 6.3622 * s))
            p.addCurve(to: CGPoint(x: 5.9824 * s, y: 7.3944 * s),
                       control1: CGPoint(x: 6.6706 * s, y: 7.079 * s),
                       control2: CGPoint(x: 6.3551 * s, y: 7.3944 * s))
            p.addCurve(to: CGPoint(x: 5.2943 * s, y: 6.7062 * s),
                       control1: CGPoint(x: 5.6097 * s, y: 7.3944 * s),
                       control2: CGPoint(x: 5.2943 * s, y: 7.0789 * s))
            p.addCurve(to: CGPoint(x: 7.3013 * s, y: 4.7 * s),
                       control1: CGPoint(x: 5.2951 * s, y: 5.5891 * s),
                       control2: CGPoint(x: 6.1838 * s, y: 4.7 * s))
            p.addLine(to: CGPoint(x: 8.7923 * s, y: 4.7 * s))
            p.addCurve(to: CGPoint(x: 10.8001 * s, y: 6.7062 * s),
                       control1: CGPoint(x: 9.9113 * s, y: 4.7 * s),
                       control2: CGPoint(x: 10.8001 * s, y: 5.5891 * s))
            p.addCurve(to: CGPoint(x: 9.7913 * s, y: 8.4275 * s),
                       control1: CGPoint(x: 10.8001 * s, y: 7.3963 * s),
                       control2: CGPoint(x: 10.4288 * s, y: 8.0563 * s))
            p.closeSubpath()
        }
        .fill(color)
        .frame(width: size, height: size)
    }
}
