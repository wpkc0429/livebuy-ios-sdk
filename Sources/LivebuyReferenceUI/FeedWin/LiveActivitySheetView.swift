import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - LiveActivitySheetView — family-2 抽獎活動參加彈窗（rb-ios-live-activity-sheet）
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 渲染抽獎活動參加彈窗，綁 DefaultActiveEvent（iOS）"
// Design: `design/templates/minimal/moments.jsx` `LBActivitySheet` +
//         rb-ios-live-activity-sheet design.md D2 / D3 / D4 / D5.
//
// This is family-2's fourth surface: a CENTERED MODAL (scrim + card, full-bleed
// overlay — same presentation convention as `WinClaimModalView`), opened by the
// `.activity` variant of `WinEntryView`, bound to `DefaultActiveEvent.currentActivity`
// (`live-activity-entry-template`, already applied — this file only READS its
// exposed public surface).
//
// ─────────────────────────────────────────────────────────────────────────────
// SINGLE-STAGE, NOT a `WinClaimModalView` four-stage clone (design.md D3)
// ─────────────────────────────────────────────────────────────────────────────
// `WinClaimModalView` runs `claim → confirmSubmit/confirmClose → submitting →
// done/fail` because the win-claim submit has an ASYNCHRONOUS backend result to
// wait for. Joining an activity (`joinCurrentActivity()` → `EVENT_JOIN_INTENT`) is
// FIRE-AND-FORGET — core never reports success/failure for it (see
// `live-activity-entry-template` design.md D3) — and the design source
// (`LBActivitySheet`) itself only has ONE local `joined` boolean, no submitting /
// result states. So this view carries exactly ONE piece of UI-local state
// (`@State private var joined`), NOT a stage machine. Do NOT grow this into a
// `WinClaimModalView`-shaped type — the two state machines are shaped differently
// for a real reason (async result vs. none) and forcing them to share code would
// drag `WinClaimModalView`'s unrelated four-stage concerns into review here.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN (mirrors `WinClaimModalView` / `WinEntryView`)
// ─────────────────────────────────────────────────────────────────────────────
//   1. `theme: ReferenceUITheme`  — FIRST positional argument.
//   2. `activity: LBActiveEvent`  — the bound snapshot value, passed BY VALUE from
//      the container (`FeedWinOverlayView` guards non-nil via `model.currentActivity`
//      before mounting this view — see that file's §3.3).
//   3. action closures (trailing, each `= nil`) — `onClose` (scrim tap → container
//      clears its presentation state), `onJoin` (CTA tap → container forwards to
//      `FeedWinModel.joinCurrentActivity()` → `DefaultPlayerTemplate
//      .joinCurrentActivity()`).
//
// This sub-view reads ONLY its passed-in `activity` value — it NEVER reaches back
// into `FeedWinModel` / `DefaultPlayerTemplate`, and it does NOT call any
// `LivebuySDK` API directly (join goes out via `onJoin`, entirely host/container
// wired). All actions `nil` still renders correctly (demo / snapshot construct
// action-free).
//
// iOS-14-safe SwiftUI only (`GeometryReader` / `ZStack` / `VStack` / `Text` /
// `Button` / `RoundedRectangle` / `Circle` are all iOS 13+). No `ScrollView` (the
// centered modal convention forbids scrolling containers, same as
// `WinClaimModalView`), no `.task` / `AsyncImage` / `NavigationStack` /
// `.foregroundStyle` / `.tint`.

/// The single-stage 抽獎活動參加彈窗 for one `LBActiveEvent`. Mirrors
/// `WinClaimModalView`'s centered scrim + card presentation, but carries only ONE
/// local「已參加」boolean (design.md D3) — there is no submitting / result stage
/// because joining an activity has no asynchronous outcome to wait for.
public struct LiveActivitySheetView: View {

    // MARK: - Inputs (documented sub-view input pattern)

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The activity this sheet presents (`DefaultActiveEvent.currentActivity`,
    /// caller-guaranteed non-nil — see `FeedWinOverlayView`'s container-level
    /// guard). Read-only; this view never mutates it.
    public let activity: LBActiveEvent

    /// Close intent (scrim tap). The design source's `LBActivitySheet` scrim is
    /// UNCONDITIONALLY clickable (`onClick={onClose}`, no stage gate — unlike
    /// `WinClaimModalView`'s scrim, which only closes on the `done` stage because
    /// that flow has interaction friction to protect). Default `nil` so demo /
    /// snapshot instances construct action-free.
    private let onClose: (() -> Void)?

    /// Join intent (CTA tap, only while not yet `joined`). The container forwards
    /// this to `FeedWinModel.joinCurrentActivity()`. Default `nil`.
    private let onJoin: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        activity: LBActiveEvent,
        onClose: (() -> Void)? = nil,
        onJoin: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.activity = activity
        self.onClose = onClose
        self.onJoin = onJoin
    }

    // MARK: - UI-local state (NOT view-model, design.md D3)

    /// Whether the CTA has been pressed this presentation. **UI local state** —
    /// `DefaultActiveEvent` / `DefaultPlayerTemplate` MUST NOT persist this (the
    /// join call is fire-and-forget with no result to reconcile against, so there
    /// is nothing for a view-model to own here — see design.md D3).
    @State private var joined: Bool = false

    // MARK: - Body

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                scrim
                card(containerWidth: geo.size.width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Scrim (unconditionally clickable → onClose, design.md D3 / source `LBActivitySheet`)

    private var scrim: some View {
        Self.scrimColor
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onClose?() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.activitySheetScrim)
    }

    // MARK: - Card (84% width, capped 320pt — same cap as `WinClaimModalView`)

    private func card(containerWidth: CGFloat) -> some View {
        let width = Self.cardWidth(containerWidth: containerWidth)
        return ZStack(alignment: .top) {
            VStack(spacing: 14) {
                titleText
                prizeNameText
                keywordText
                ctaButton
                footer
            }
            .padding(.top, 46)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(width: width)
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 24)

            // The trophy badge floats OUTSIDE the clipped card (top: -30 in the
            // design source) — same two-layer ZStack technique as
            // `WinClaimModalView.cardShell` (an inner clipped layer + an outer
            // unclipped layer for the badge), for the same reason: a badge placed
            // INSIDE the clipped card would be cut off by `clipShape`.
            badge
                .offset(y: -30)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.activitySheet)
    }

    /// Card width — design source `width: '84%', maxWidth: 320` (same rule as
    /// `WinClaimModalView.cardWidth`).
    static func cardWidth(containerWidth: CGFloat) -> CGFloat {
        min(containerWidth * 0.84, 320)
    }

    // MARK: - Content

    private var titleText: some View {
        Text(activity.title)
            .font(.system(size: 20 * theme.fontScale, weight: .heavy))
            .foregroundColor(theme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 獎品名稱 — `activity.award.first?.name`（空值退回空字串，design.md /
    /// spec.md 明確容忍空 award 陣列，不是 fallback 佔位文案）。
    private var prizeNameText: some View {
        Text(activity.award.first?.name ?? "")
            .font(.system(size: 15 * theme.fontScale, weight: .semibold))
            .foregroundColor(theme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 「留言關鍵字【{keyword}】即可參加抽獎！」— accent 色文字（design source 固定格式，
    /// `keyword` 為空時仍照格式呈現空括號，忠實反映 `activity.keyword ?? ""`，不臆測替代文案）。
    private var keywordText: some View {
        Text(Self.keywordLabel(keyword: activity.keyword ?? ""))
            .font(.system(size: 14 * theme.fontScale, weight: .bold))
            .foregroundColor(theme.accent)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Pure: the keyword call-to-action string (design source's fixed format).
    static func keywordLabel(keyword: String) -> String {
        "留言關鍵字【\(keyword)】即可參加抽獎！"
    }

    /// Pure: whether a CTA tap should actually trigger a join call, given the
    /// current `joined` state. Split out so this decision is unit-testable without
    /// rendering the view — the `@State` WRITE itself is left as an untested,
    /// reviewed one-line dispatch (mirrors `FeedWinOverlayView.legalLinkRoute(for:)`
    /// / `WinClaimModalView.stage(phase:...)`: `@State` writes performed on a view
    /// instance SwiftUI never actually installed are silently discarded, so the
    /// mutation itself has no unit-testable surface — only the decision does).
    static func shouldJoin(joined: Bool) -> Bool {
        !joined
    }

    /// 「立即參加」/「已參加」CTA — 按下呼叫 `onJoin?()` 並本地切 `joined = true`
    /// （design.md D3：fire-and-forget，無非同步結果可等）。`joined` 後 disabled + 灰底。
    private var ctaButton: some View {
        Button(action: {
            guard Self.shouldJoin(joined: joined) else { return }
            joined = true
            onJoin?()
        }) {
            Text(joined ? Self.joinedLabel : Self.joinLabel)
                .font(.system(size: 16 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(joined ? Self.joinedBackground : theme.accent))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(joined)
        .padding(.top, 4)
        .accessibilityIdentifier(LBAccessibilityID.activitySheetCta)
    }

    /// footer「使用條款｜隱私政策」— 純文字版面，未接任何連結 / action（連結目標未定案，
    /// 沿用 `WinClaimModalView` 舊有「先留版面、不接實際連結」的既有作法；本 change 的
    /// props 清單本身也不帶 footer 連結 callback，見 tasks.md 2.2）。
    private var footer: some View {
        HStack(spacing: 0) {
            Text(Self.footerTerms)
            Text(" | ").opacity(0.5)
            Text(Self.footerPrivacy)
        }
        .font(.system(size: 12.5 * theme.fontScale, weight: .medium))
        .foregroundColor(Self.textDim)
    }

    // MARK: - Badge (60pt, 浮出卡頂外 — accent 填色 + 白底圓形 + 4pt surface-bg 描邊)
    //
    // design.md / spec.md: 重用 `WinEntryGiftGlyph`，但這裡是 accent 填色（NOT `.win`
    // 入口的硬寫死 `#F03246`）、白底圓形（NOT `WinClaimModalView.giftBadge` 的 accent
    // 漸層底）—— 對齊 design 原始碼 `LBActivitySheet` 的 `giftSvg(30, accent)` 畫在白底圓上。

    private var badge: some View {
        let scale: CGFloat = 30 / 200
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return ZStack {
            Circle()
                .fill(Color.white)
            ZStack {
                WinEntryGiftGlyph.outlinePath()
                    .applying(transform)
                    .fill(theme.accent, style: FillStyle(eoFill: true))
                WinEntryGiftGlyph.innerPath()
                    .applying(transform)
                    .fill(Color.white, style: FillStyle(eoFill: true))
            }
            .frame(width: 30, height: 30)
        }
        .frame(width: 60, height: 60)
        .overlay(Circle().stroke(theme.background, lineWidth: 4))
        .shadow(color: Color.black.opacity(0.2), radius: 11, x: 0, y: 8)
    }

    // MARK: - Design tokens (design-literal, mirrors `WinClaimModalView`'s convention)

    static let scrimColor = Color.black.opacity(0.6)
    /// 「已參加」disabled CTA 底色（design source `#C9CDD3`）。
    static let joinedBackground = Color(hex: "#C9CDD3") ?? Color.gray.opacity(0.4)
    /// `theme.surface.textDim`（footer 次要文字，與 `WinClaimModalView.textDim` 同一色值）。
    static let textDim = Color(hex: "#6B6775") ?? Color.gray

    static let joinLabel = "立即參加"
    static let joinedLabel = "已參加"
    static let footerTerms = "使用條款"
    static let footerPrivacy = "隱私政策"
}

// MARK: - Test / preview seed
//
// `joined` is `@State`, unreachable from outside via the public initializer — that
// is BY DESIGN (D3: it always starts `false`, flipping only via the CTA). Mirrors
// `WinClaimModalView.makeSeededForTesting`'s same underscore-storage technique
// (`docs/unit-test-discipline.md` §3's `*ForTesting` naming convention).
// **Production code never calls this.**
//
// This module cannot offer a production-level `LiveActivitySheetView.demo(...)`
// convenience the way `WinEntryView.demo(...)` does: `LBActiveEvent`'s memberwise
// `init` is deliberately `internal` to `LivebuySDK` (host apps read the public
// fields but never construct this value — see `LBModels.swift`'s doc comment), so
// only `@testable import LivebuySDK` code (the snapshot test) can build one.

extension LiveActivitySheetView {

    /// Test-only / preview seed: build a view for a given `activity` with `joined`
    /// pre-set. Production code never calls this.
    static func makeSeededForTesting(
        theme: ReferenceUITheme,
        activity: LBActiveEvent,
        joined: Bool = false
    ) -> LiveActivitySheetView {
        var view = LiveActivitySheetView(theme: theme, activity: activity)
        view._joined = State(initialValue: joined)
        return view
    }
}
