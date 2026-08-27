import SwiftUI

// MARK: - SheetGrabHandle — the shared bottom-sheet grab handle (SheetKit)
//
// ONE definition of the `LBPBottomSheet` handle (a 36×4 rounded pill, centered, with the
// design's top/bottom padding), replacing the 4 self-drawn copies that previously lived in
// `VideoInfoPanelView` / `ProductListView` / `ProductDetailSheetView` /
// `NotifyRestockSheetView`. `BottomSheetPresenter` draws this at the card's top and binds the
// drag-to-dismiss gesture to it (so dragging never eats a CTA / tab tap). iOS-14-safe.
struct SheetGrabHandle: View {

    /// The handle pill color — the house `strokeStrong` design literal (`#D8D5DE`), the SAME
    /// value the leaf sheets used, so the handle stays pixel-identical after consolidation.
    private static let handleColor = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)

    /// Fixed total height of the whole draggable row — the single named source of truth for
    /// this value (rb-ios-sheetkit-resize-ceiling-handle-overshoot-fix established the constant;
    /// rb-ios-sheetkit-drag-row-height enlarged it from `16` to `44`, replacing the original
    /// `8pt top padding + 4pt 36×4 pill + 4pt bottom padding` breakdown with a single
    /// `.frame(height:)` that centers the SAME 36×4pt pill — the pill's own size/color/corner-
    /// radius are unchanged, only the surrounding touch target grew, closer to the commonly
    /// recommended ~44pt minimum mobile touch target). `BottomSheetChrome.resizedHeightFraction
    /// (...)` reads this to keep the FULL card (handle + `sheetContent()`) clamped at the shared
    /// 80% resize ceiling (`rb-ios-sheetkit-resize-ceiling-eighty-percent`, originally 90%) —
    /// without it, the ceiling clamp only bounded `sheetContent()` itself, and this handle's
    /// height stacked on top pushed the visible card past the ceiling (confirmed, pre-fix, via
    /// Simulator pixel measurement: ~91.7-91.9% at full drag against the then-90% ceiling,
    /// matching the then-16pt constant almost exactly).
    ///
    /// rb-ios-sheetkit-drag-row-height-32pt shrank this from `44` to `32` after the user saw the
    /// 44pt row rendered and reported it felt visually too spacious — the whole VISIBLE row
    /// (handle pill + surrounding whitespace) grows with this constant, not just an invisible
    /// touch target, so 44pt left a noticeably large empty ring around the 4pt pill. A "shrink
    /// the visible row, overlay a separate larger invisible hit target" alternative was
    /// considered and rejected: it would extend the hit target down into the header's own
    /// search/close button touch areas, needing extra horizontal safe-area handling for a
    /// problem that's purely about visual whitespace, not touch-target size. `32` stays well
    /// above the original `16` (still comfortably larger than the pre-drag-row-height target)
    /// while looking noticeably less empty than `44`.
    static let fixedHeight: CGFloat = 32

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 99)
                .fill(Self.handleColor)
                .frame(width: 36, height: 4)
            Spacer(minLength: 0)
        }
        // `.frame(height:)` (rb-ios-sheetkit-drag-row-height, replacing the prior
        // `.padding(.top, 8) + .padding(.bottom, 4)` — 16pt total) — binds the whole row's
        // height directly to `fixedHeight` (SwiftUI's default `.center` frame alignment
        // vertically centers the 4pt-tall pill inside it) instead of two independently
        // hand-tuned padding literals that would need to be recomputed in lockstep with any
        // future change to `fixedHeight`.
        .frame(height: Self.fixedHeight)
    }
}
