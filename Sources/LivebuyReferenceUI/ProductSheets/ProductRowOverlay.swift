import Foundation

/// Playback mode that decides a product-list row's thumbnail overlay
/// (rb-ios-product-row-status-overlay). Distinct from the real-frame `live`
/// flag (photo loading) — this is VOD vs active-live vs replay.
public enum ProductRowMode: Equatable {
    case vod      // 純點播：可 seek 到商品介紹片段 → 播放 icon
    case live     // 直播中：無未來可跳 → 正在介紹的商品標「介紹中」、其餘無 icon
    case replay   // 直播回放：依 begin_time/end_time vs 當下播放秒數逐商品判「介紹中」
}

/// Pure decision for a product-list row's thumbnail overlay AND the row's share
/// icon visibility. Unit-testable in isolation (rb-ios-product-row-status-overlay
/// / rb-ios-live-hide-product-share / rb-ios-product-row-vod-intro-mask). The play
/// affordance and the「介紹中」label are mutually exclusive on any single row.
///
/// - VOD (rb-ios-product-row-vod-done-state-removed, 2026-09-07 撤回
///   rb-ios-product-row-vod-intro-mask 的三態): TWO-phase, mirroring `.replay`
///   below — driven by `position` vs the product's `[beginTime, endTime)`
///   window. `now` (`beginTime <= position < endTime`, i.e. the product is
///   currently in core's `LBPlaybackProgress.vodActiveProducts`) → 介紹中
///   (`showIntroducing`); everything else (`position < beginTime` OR
///   `position >= endTime`) → the play affordance (`showPlay`). There is no
///   "done" state for VOD anymore — a row always shows one overlay or the
///   other, same structure as `.replay` (visual skin still differs: full-bleed
///   equalizer mask vs replay's bottom banner). Missing `beginTime` or
///   `endTime` falls back to the pre-existing behavior — always the play
///   affordance, so a VOD product with no scheduled intro window never silently
///   loses its seek affordance. Share icon shown regardless of phase (a VOD
///   product has a real `beginTime` a share link can point at).
/// - active live: 介紹中 ⟺ `isNarrating` (the `narrate_status == 2` product);
///   never the play affordance (live has no future to scrub to). Share icon
///   HIDDEN (rb-ios-live-hide-product-share, design R12) — a genuinely-live
///   product has no settled "start time" a share link could carry.
/// - replay: TWO-phase (unlike VOD's three) — 介紹中 ⟺ the current playback
///   `position` is inside the product's `[beginTime, endTime]` window
///   (inclusive); otherwise the play affordance (seek to its segment). There is
///   no "done" state for replay — a row always shows one overlay or the other.
///   `isNarrating` is ignored for replay (`introducingProductId` is non-nil only
///   during active live). Share icon shown — replay products have real
///   `beginTime`/`endTime`, same semantics as VOD.
///   EXCEPTION (rb-ios-replay-never-introduced-no-ui): `beginTime == 0 &&
///   endTime == 0` is a distinct backend sentinel meaning this product was
///   NEVER narrated during the original live broadcast (not merely "missing
///   data", which is the existing `nil` fallback below) — a zero-length
///   `[0, 0]` window can never legitimately be a real intro segment. Neither
///   the play affordance nor 介紹中 SHALL show for that row (both `false`) —
///   a THIRD, distinct state from the two-phase "always show something"
///   description above, deliberately scoped to this one sentinel.
public enum ProductRowOverlay {
    public static func decide(
        mode: ProductRowMode,
        isNarrating: Bool,
        beginTime: Int?,
        endTime: Int?,
        position: Int
    ) -> (showPlay: Bool, showIntroducing: Bool, showShare: Bool) {
        let showShare = mode != .live
        switch mode {
        case .vod:
            guard let begin = beginTime, let end = endTime else {
                // No scheduled intro window — pre-existing always-play fallback.
                return (showPlay: true, showIntroducing: false, showShare: showShare)
            }
            let isNow = begin <= position && position < end
            return (showPlay: !isNow, showIntroducing: isNow, showShare: showShare)
        case .live:
            return (showPlay: false, showIntroducing: isNarrating, showShare: showShare)
        case .replay:
            if isReplayNeverIntroduced(beginTime: beginTime, endTime: endTime) {
                // Never introduced during the original live broadcast — no play
                // affordance, no 介紹中 (rb-ios-replay-never-introduced-no-ui).
                return (showPlay: false, showIntroducing: false, showShare: showShare)
            }
            let inWindow = beginTime != nil && endTime != nil
                && beginTime! <= position && position <= endTime!
            return (showPlay: !inWindow, showIntroducing: inWindow, showShare: showShare)
        }
    }

    /// The `.replay`-only「never introduced」sentinel (rb-ios-replay-never-introduced-no-ui):
    /// `beginTime == 0 && endTime == 0` is a backend sentinel meaning this product was NEVER
    /// narrated during the original live broadcast — distinct from `nil` (missing data).
    /// Exposed (not `private`) so callers that need to know "is this row's thumbnail tap
    /// meaningful" (e.g. the seek-and-dismiss tap handler) can reuse the SAME condition
    /// `decide(...)` uses, rather than re-deriving it and risking drift.
    public static func isReplayNeverIntroduced(beginTime: Int?, endTime: Int?) -> Bool {
        beginTime == 0 && endTime == 0
    }
}
