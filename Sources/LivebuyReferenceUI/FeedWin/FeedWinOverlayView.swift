import SwiftUI
import UIKit
import SafariServices
import LivebuySDK
import LivebuyUI

// MARK: - FeedWinOverlayView — family-2 feed + win container (SKELETON)
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, 3 surfaces)
// Design: rb-ios-feed-win design.md D-1 / D-2 / D-3 / D-4.
//
// The top-level family-2 container (this is the design's `FeedWinView` role; the
// file/type name is `FeedWinOverlayView` to read as an overlay composited over
// the player). It composes the family-2 surface sub-views over the live video
// area (originally THREE — rb-ios-live-activity-sheet, 2026-08-29, added a
// fourth):
//
//   1. ChatFeedView          — merged chat-feed stream (D-2 #1, `LBLiveChatStream`)
//   2. WinEntryView          — floating win-claim entry badge (D-3 #2, `LBWinEntry`)
//   2b. WinEntryView         — floating activity-join entry badge, STACKED below #2
//                              (`variant: .activity`, rb-ios-live-activity-sheet,
//                              SAME type as #2 — see design.md D1)
//   3. WinClaimModalView     — 四階段領獎 modal（含 email 輸入），presented on demand
//                              (D-4 #3, `LBWinSheet`)
//   4. LiveActivitySheetView — 抽獎活動參加彈窗（單階段），presented on demand
//                              (rb-ios-live-activity-sheet, `LBActivitySheet`)
//
// This is the SKELETON: it owns the layout + a `FeedWinModel` + the resolved
// `ReferenceUITheme` + the sheet presentation state, and composes the three
// surface sub-views BY TYPE NAME. The three sub-view TYPES are produced by the
// three parallel surface agents that run after this skeleton — see the "SUB-VIEW
// INPUT PATTERN" contract below, which every surface agent MUST implement
// verbatim so the container's call sites match.
//
// Until all three surface sub-views exist, this file will not compile on its own —
// that is expected (the surface agents land the types). The container's job is to
// FIX the layout + the call-site shape so the parallel agents converge.
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `Spacer` / manual padding are all
// iOS-13+; no `@available` guard needed here. Any surface that reaches for a >14
// API must guard it inside its own sub-view (D §iOS-14-safe).
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 3 parallel surface agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-2 surface sub-view is a `public struct …: View` whose initializer
// takes, IN THIS ORDER (identical convention to family-1 player-shell):
//
//   1. `theme: ReferenceUITheme`            — the resolved reference-ui theme
//                                             (FIRST positional argument, always).
//   2. its bound SNAPSHOT VALUE(S)          — the read-only state it renders,
//                                             passed BY VALUE from FeedWinModel
//                                             (never the model, never the template).
//   3. optional action closures            — trailing, each defaulting to `nil`
//                                             (`onX: (() -> Void)? = nil`, etc.).
//                                             The container does NOT own actions;
//                                             the host wires submit / join through
//                                             the template / upstream exits.
//
// Concretely, the three surface agents implement EXACTLY these initializers:
//
//   ChatFeedView(
//       theme: ReferenceUITheme,
//       items: [LBFeedItem],
//       onJoinEvent: ((_ eid: Int, _ keyword: String) -> Void)? = nil)
//
//   WinEntryView(
//       theme: ReferenceUITheme,
//       unclaimedCount: Int,
//       onTap: (() -> Void)? = nil)
//
//     rb-ios-live-activity-sheet (2026-08-29) added `variant: WinEntryVariant = .win`
//     and `isActive: Bool = false` (source-compatible defaults) so the SAME type
//     also renders the activity-join entry (`variant: .activity`) — see
//     `WinEntryView.swift` for the full current signature.
//
//   WinClaimModalView(
//       theme: ReferenceUITheme,
//       winner: LBWinner,
//       presentation: LBAwardPresentation,
//       resultState: LBAwardClaimResultState?,
//       submitInFlight: Bool = false,
//       pageCount: Int = 1,                    // rb-ios-win-claim-pagination, R27
//       pageIndex: Int = 0,                    // rb-ios-win-claim-pagination, R27
//       onSubmit: ((String) -> Void)? = nil,   // 帶使用者輸入的 email
//       onDismiss: (() -> Void)? = nil,
//       onPage: ((Int) -> Void)? = nil,        // rb-ios-win-claim-pagination, R27
//       editable: Bool = true)
//
//   LiveActivitySheetView(                     // rb-ios-live-activity-sheet, NEW
//       theme: ReferenceUITheme,
//       activity: LBActiveEvent,
//       onClose: (() -> Void)? = nil,
//       onJoin: (() -> Void)? = nil)
//
// Rules every surface agent honours:
//   • FIRST positional arg is `theme:`. Snapshot values are passed BY VALUE.
//   • Action closures are LAST, each `… = nil` (the container passes the host /
//     template-wired closure or omits it). A surface sub-view MUST render
//     correctly with all actions nil (so demo / snapshot tests construct it
//     action-free).
//   • A surface sub-view reads ONLY its passed-in values — it MUST NOT reach back
//     into FeedWinModel or DefaultPlayerTemplate (one-way data flow, D-1).
//   • `ChatFeedView` dispatches its rows by `LBFeedItem.kind` internally
//     (`.chat` → ChatLineRow, `.eventJoin` → EventJoinLineRow, `.activity(tier:)`
//     → ActivityLineRow). `text` is the backend-prebuilt full string — sub-views
//     MUST NOT split it into fields (D-2).
//   • `WinClaimModalView` 跑四階段領獎流程（claim / confirmSubmit / submitting /
//     done / fail —— `confirmClose` 已隨 R27 退役），**含 email 輸入欄**
//     （EMAIL-LESS 已退役）。`onSubmit` 帶使用者輸入的 email，funnel 到
//     `DefaultWinClaim.submit(winner:email:)`；`submitting` 綁 view-model
//     `submitInFlight`、`done`/`fail` 綁 `resultState`；外層 scrim（唯一關閉入口，
//     任一 stage 皆無條件觸發，R27）→ `onDismiss`（**純 dismiss**，不放棄中獎資格）。
//     `pageCount`/`pageIndex`/`onPage`（R27，`rb-ios-win-claim-pagination`）讓使用者
//     滑動 / 點分頁圓點在多筆待領獎者間切換，容器依既有 `unclaimedWinners` 依索引讀取
//     （不新增第二份清單真相）。
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available` inside the sub-view.
// ─────────────────────────────────────────────────────────────────────────────

/// The family-2 feed-win container. Drives layout for the merged chat-feed
/// stream + the floating win-entry badge over the video area, and presents the
/// 四階段領獎 modal（含 email 輸入）on demand; reads a `FeedWinModel` (republished from
/// a live `DefaultPlayerTemplate` or constructed deterministically) and paints
/// with the resolved `ReferenceUITheme`.
public struct FeedWinOverlayView: View {

    /// The republished, read-only feed-win snapshot.
    @ObservedObject public var model: FeedWinModel

    /// The resolved reference-ui theme.
    public let theme: ReferenceUITheme

    /// Bottom inset applied ONLY to the merged chat-feed stream so its newest
    /// (bottom) rows sit ABOVE the LIVE bottom bar (`LiveBottomBarView`) instead
    /// of being occluded by it. The chat feed and the LIVE bar share the same
    /// player-overlay space (both composed in `PlayerOverlayRootView`'s ZStack),
    /// so the host passes the LIVE-bar clearance here. Default `0` keeps the demo /
    /// snapshot path byte-identical; it does NOT shift the centered claim modal or
    /// the already-anchored win-entry badge — only the chat feed sub-view.
    public let chatBottomInset: CGFloat

    /// Whether the chat feed is the SCROLLABLE variant (runtime) so the user can scroll
    /// up to view history. `true` → `ChatFeedView` is fed the deeper `feedHistory` and
    /// `hostScrollable: true`; `false` (default / demo / snapshot) → the ambient
    /// `feedItems` + non-scrollable path (baseline byte-identical).
    public let chatScrollable: Bool

    /// Whether the family-1 info panel (`VideoInfoPanelView`, a bottom sheet + dim scrim
    /// composed in the lower `PlayerShellView` layer) is currently presented. The chat
    /// feed sits ABOVE that layer and its scrollable variant eats hit-testing, so while
    /// the info panel is up the chat would occlude it / swallow taps meant for the sheet.
    /// `true` → the chat feed sub-view is hidden + non-interactive (so the panel's scrim
    /// cleanly covers the background and the sheet is fully usable); `false` (default /
    /// demo / snapshot) → unchanged (baseline byte-identical). ONLY the chat feed is
    /// affected — the centered claim modal / win-entry badge are not.
    public let infoPanelOpen: Bool

    /// Whether the player shell's「乾淨模式」(long-press toggle, `PlayerShellView`'s private
    /// `@State cleanMode`) is on. `PlayerShellView` cannot reach this sibling view directly (it
    /// is composed alongside it, not inside its render tree — `MinimalDesign.playerOverlay`
    /// mirrors the state via `onCleanModeChange` and forwards it here), so it is threaded through
    /// as a plain parameter (rb-ios-clean-mode-hide-chat-feed). `true` → the chat feed sub-view
    /// is hidden + non-interactive, same opacity/hit-testing treatment as `infoPanelOpen` above
    /// (merged into the same judgment, not a second independent hide). `false` (default / demo /
    /// snapshot) → unchanged (baseline byte-identical).
    ///
    /// ⚠️ `WinEntryView` (win-claim entry badge) and its claim sheet below are NOT gated by
    /// `cleanMode` (nor by `infoPanelOpen`) — the design (`screens.jsx`'s `LBWinEntry`) never
    /// gave them a `!cleanMode` gate, so the winner must always be able to see and tap into their
    /// claim regardless of clean mode. Do not extend `cleanMode` to that branch.
    public let cleanMode: Bool

    /// Whether to render the merged chat-feed stream at all. It is a LIVE-only surface, and its
    /// full-bleed scrollable variant eats hit-testing; in VOD (`false`) it would occlude / swallow
    /// taps on the VOD side rail, so the container passes `false` to drop it entirely (the
    /// `ScrollView` is removed, not just hidden — rb-ios-hide-chat-feed-in-vod). `true` (default /
    /// demo / snapshot) → rendered as before (baseline byte-identical). ONLY the chat feed is
    /// gated — the win-entry badge / claim modal are unaffected.
    public let showsChatFeed: Bool

    /// Trailing inset applied ONLY to the merged chat-feed stream so it stays in the design's
    /// LEFT column (`live-chrome.jsx` `LBLiveChatOverlay` `right:152`) and does NOT extend into
    /// / occlude the bottom-right `LBLivePinnedCard` column — nor let the chat `ScrollView` eat
    /// taps meant for that product card. Default `0` keeps the demo / snapshot path
    /// byte-identical; it does NOT shift the centered claim modal or the win-entry badge.
    public let chatTrailingInset: CGFloat

    /// Leading inset applied ONLY to the merged chat-feed stream so its left edge aligns with
    /// the LIVE bottom bar's bag button left margin instead of sitting flush against the screen
    /// edge (rb-ios-live-chat-card-edge-align). Default `0` keeps the demo / snapshot path
    /// byte-identical; it does NOT shift the centered claim modal or the win-entry badge — only
    /// the chat feed sub-view. Same opt-in pattern as `chatBottomInset` / `chatTrailingInset`.
    public let chatLeadingInset: CGFloat

    /// The winner the claim sheet is currently presented for, if any. Local
    /// presentation state only — the sheet CONTENT (award detail / CTA / result)
    /// is driven by the model; this just governs which winner is on screen.
    @State private var claimingWinner: LBWinner?

    /// The page (index into `model.unclaimedWinners`) the claim modal is currently
    /// showing (`rb-ios-win-claim-pagination`, R27). Local presentation state only —
    /// this container does NOT hold a second copy of `unclaimedWinners`; `onPage(_:)`
    /// always re-reads the LIVE list by this index (design.md D2). Reset to `0` by
    /// `presentNextClaim()` on every fresh open.
    @State private var claimPageIndex: Int = 0

    /// Whether `LiveActivitySheetView` is currently presented
    /// (rb-ios-live-activity-sheet). A plain Bool — NOT a captured `LBActiveEvent`
    /// value — because `DefaultActiveEvent.currentActivity` is deliberately a
    /// live-pull, never-cached read (see that type's doc comment); capturing it
    /// into `@State` here would create a second, potentially-stale copy. The
    /// sheet's CONTENT is read fresh from `model.currentActivity` at render time
    /// (see the `if showingActivitySheet, let activity = model.currentActivity`
    /// guard below) — this flag only governs whether it is on screen.
    @State private var showingActivitySheet: Bool = false

    /// The resolved URL of a footer legal link (`LBLegalLinks.termsOfUse` /
    /// `.privacyPolicy`) currently presented in-app, if any (rb-ios-win-claim-footer-links).
    /// Set only by `openLegalLink(_:)` when `LBURLOpenPolicy.decide(_:)` judges `.inApp`;
    /// drives the `.sheet` below. Local presentation state only — this container does
    /// NOT own the legal-link CONTENT (the URL comes from core `LBLegalLinks`).
    @State private var presentedLegalLink: URL?

    public init(model: FeedWinModel, theme: ReferenceUITheme,
                chatBottomInset: CGFloat = 0, chatScrollable: Bool = false,
                infoPanelOpen: Bool = false, chatTrailingInset: CGFloat = 0,
                chatLeadingInset: CGFloat = 0,
                showsChatFeed: Bool = true,
                cleanMode: Bool = false) {
        self.model = model
        self.theme = theme
        self.chatBottomInset = chatBottomInset
        self.chatScrollable = chatScrollable
        self.infoPanelOpen = infoPanelOpen
        self.chatTrailingInset = chatTrailingInset
        self.chatLeadingInset = chatLeadingInset
        self.showsChatFeed = showsChatFeed
        self.cleanMode = cleanMode
    }

    public var body: some View {
        ZStack {
            // The merged chat-feed stream — left-aligned, newest at the bottom,
            // top gradient mask (the surface agent paints this). Full-bleed under
            // the win entry. Surface 1. LIVE-only: dropped ENTIRELY in VOD (showsChatFeed ==
            // false) so its full-bleed ScrollView doesn't occlude / eat the VOD side rail's
            // taps (rb-ios-hide-chat-feed-in-vod).
            if showsChatFeed {
            ChatFeedView(
                theme: theme,
                // Scrollable variant binds the deeper history (scroll up for history);
                // the ambient / snapshot path keeps the N=7 feedItems.
                items: chatScrollable ? model.feedHistory : model.feedItems,
                hostScrollable: chatScrollable,
                // 置頂留言（chat-pinned-message-render ⑤c）；nil → 無橫幅（snapshot 中性）。
                pinned: model.pinned,
                // 主播名（純顯示，rb-ios-loading-announce-restyle）→ `.eventJoin` 列的主播名 +
                // 「主播」badge header。
                hostName: model.hostName,
                onJoinEvent: { eid, keyword in
                    // The唯一 interactive row's「加入活動」intent → upstream exit
                    // (host wired) via the model's thin forwarder.
                    model.joinEvent(eid: eid, keyword: keyword)
                })
                // Keep the newest (bottom) rows ABOVE the LIVE bottom bar — applied
                // ONLY to the chat feed (NOT the centered claim modal / win-entry).
                .padding(.bottom, chatBottomInset)
                // Keep the chat in the design's LEFT column (LBLiveChatOverlay right:152) so it
                // does not occlude / eat taps on the bottom-right LBLivePinnedCard column —
                // applied ONLY to the chat feed (rb-ios-live-pinned-card-appears).
                .padding(.trailing, chatTrailingInset)
                // Align the chat's left edge with the LIVE bottom bar's bag button left margin
                // instead of sitting flush against the screen edge — applied ONLY to the chat
                // feed (rb-ios-live-chat-card-edge-align).
                .padding(.leading, chatLeadingInset)
                // While the info panel (lower-layer bottom sheet + scrim) is up, hide +
                // disable the chat feed so it neither occludes the sheet nor swallows its
                // taps (the panel's scrim then cleanly covers the background). opacity (not
                // removal) preserves the chat's scroll/auto-stick state for when it returns.
                // Also hidden while clean mode is on (rb-ios-clean-mode-hide-chat-feed,
                // parity with Android/Flutter) — merged into the SAME judgment, not a second
                // independent hide. ONLY the chat feed — the win-entry badge / claim modal
                // below are untouched by either condition.
                .opacity((infoPanelOpen || cleanMode) ? 0 : 1)
                .allowsHitTesting(!infoPanelOpen && !cleanMode)
            }

            // Floating win-claim entry badge — right side. R27 (`rb-ios-win-claim-pagination`)
            // FLIPPED the iOS stacking order: this entry is now SECONDARY — it sits at the
            // primary slot `top: 25%` only when the activity entry below is NOT showing
            // (`model.currentActivity == nil`); when the activity entry IS showing, this one
            // is pushed down to `top: 25% + 58pt` (58pt = the entry's own 48pt height + 10pt
            // gap). Mirrors the exact conditional-offset pattern the activity entry used to
            // use (previously: win unconditional primary, activity conditional secondary —
            // now reversed). Drawn ONLY when `unclaimedCount > 0` (the sub-view itself
            // no-draws at 0; the container also early-returns the tap when nothing to claim).
            // Surface 2.
            //
            // ⚠️ NOT gated by `cleanMode` (nor `infoPanelOpen`) — `WinEntryView` and its claim
            // sheet below are intentionally excluded from the clean-mode hide rule (design
            // `screens.jsx`'s `LBWinEntry` carries no `!cleanMode` gate); do not extend
            // `cleanMode` to this branch (rb-ios-clean-mode-hide-chat-feed).
            GeometryReader { geo in
                WinEntryView(
                    theme: theme,
                    unclaimedCount: model.unclaimedCount,
                    onTap: { presentNextClaim() })
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: geo.size.height * 0.25
                        + (model.currentActivity != nil ? 58 : 0))
            }

            // Floating activity-join entry badge — right side. R27 FLIPPED this to be the
            // PRIMARY slot: unconditional `top: 25%` (previously conditional/secondary,
            // stacked below the win entry — see the win entry's comment above for the mirror
            // image of this same flip). Bound to `model.currentActivity` (republished from
            // `DefaultActiveEvent.currentActivity`, `live-activity-entry-template`). The view
            // is ALWAYS instantiated here (same as the win-entry above) — visibility is
            // decided INSIDE `WinEntryView`'s own body via `isActive`, not by conditionally
            // mounting it here (design.md D2: symmetric with how the win-entry's
            // `unclaimedCount > 0` gate is placed). Surface 2b.
            //
            // ⚠️ NOT gated by `cleanMode` (nor `infoPanelOpen`) — same exemption as
            // the win-entry above (the design never gave either entry a `!cleanMode`
            // gate); do not extend `cleanMode` to this branch either.
            GeometryReader { geo in
                WinEntryView(
                    theme: theme,
                    variant: .activity,
                    isActive: model.currentActivity != nil,
                    onTap: { showingActivitySheet = true })
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: geo.size.height * 0.25)
            }

            // 抽獎活動參加彈窗 (LBActivitySheet) — a CENTERED MODAL, same full-bleed
            // overlay convention as the 領獎 modal below. Single-stage (design.md
            // D3): reads `model.currentActivity` FRESH at render time rather than a
            // captured value (see `showingActivitySheet`'s doc comment) so it never
            // shows a stale activity. Surface 4.
            if showingActivitySheet, let activity = model.currentActivity {
                LiveActivitySheetView(
                    theme: theme,
                    activity: activity,
                    onClose: { showingActivitySheet = false },
                    onJoin: { model.joinCurrentActivity() })
            }

            // 四階段領獎 modal (LBWinSheet) — a CENTERED MODAL presented as a
            // full-bleed overlay layer (NOT a native bottom `.sheet`) so it matches
            // the design's centered-card-over-scrim form factor. The view owns its
            // own dark scrim. Surface 3.
            //
            // 🔴 關閉＝**純 dismiss**：`model.dismissClaim()` 只清 view-model 的
            // `resultState` / `submitInFlight`，本容器只清自己的呈現綁定 —— MUST NOT
            // 移除未領中獎 / 呼叫 API / 遞減徽章（設計稿的「放棄資格」文案是刻意的 UX
            // 摩擦，行為不跟隨；R13 刻意分歧 1/2）。R27：`confirmClose` 二次確認退役，
            // 唯一關閉入口是外層 scrim，任一 stage 皆無條件直接觸發此 `onDismiss`。
            //
            // 分頁能力（R27，`rb-ios-win-claim-pagination`，design.md D1/D2）：
            //   • `pageCount`/`pageIndex` 由本容器目前的 `model.unclaimedWinners` /
            //     `claimPageIndex` 鏡像傳入——本容器 MUST NOT 複製第二份待領獎者清單。
            //   • `.id(winner.id)` 讓每次翻頁到不同 winner 都是一次乾淨 remount，
            //     `WinClaimModalView` 的 `@State`（`phase` / `email` / …）不會沿用上一位
            //     winner 殘留的互動相位（design.md D1；SwiftUI 只在 identity 改變時才重置
            //     `@State`，`winner:` 參數值改變本身不會）。
            if let winner = claimingWinner {
                WinClaimModalView(
                    theme: theme,
                    winner: winner,
                    presentation: presentation(for: winner),
                    resultState: model.resultState,
                    submitInFlight: model.submitInFlight,
                    pageCount: model.unclaimedWinners.count,
                    pageIndex: claimPageIndex,
                    onSubmit: { email in model.submitClaim(for: winner, email: email) },
                    onDismiss: {
                        model.dismissClaim()
                        claimingWinner = nil
                    },
                    onPage: { index in onPage(index) },
                    // footer「使用條款 | 隱私政策」（rb-ios-win-claim-footer-links）— the
                    // container is the ONLY layer that judges HOW a legal link opens
                    // (`LBURLOpenPolicy.decide(_:)`); `WinClaimModalView` only reports WHICH
                    // segment was tapped.
                    onOpenTermsOfUse: { openLegalLink(LBLegalLinks.termsOfUse) },
                    onOpenPrivacyPolicy: { openLegalLink(LBLegalLinks.privacyPolicy) })
                    .id(winner.id)
            }
        }
        // Footer legal-link in-app presentation (rb-ios-win-claim-footer-links). A plain
        // `.sheet(isPresented:)` computed from `presentedLegalLink` — `URL` is not
        // `Identifiable` and this state has exactly one reader, so a wrapper type solely to
        // satisfy `.sheet(item:)` would add a type without adding clarity (see design.md D-G).
        .sheet(isPresented: Binding(
            get: { presentedLegalLink != nil },
            set: { if !$0 { presentedLegalLink = nil } }
        )) {
            if let url = presentedLegalLink {
                SafariView(url: url)
            }
        }
    }

    /// Open the claim sheet on the EARLIEST unclaimed winner (D-3). No-op when
    /// nothing is claimable (`unclaimedCount == 0`). Resets `claimPageIndex` to `0` first
    /// (`rb-ios-win-claim-pagination`, design.md D2) so a fresh open never starts mid-page.
    private func presentNextClaim() {
        guard let next = model.nextUnclaimedWinner else { return }
        claimPageIndex = 0
        claimingWinner = next
    }

    /// `WinClaimModalView.onPage(_:)` handler (`rb-ios-win-claim-pagination`, design.md D2).
    /// ALWAYS re-derives `claimingWinner` from the LIVE `model.unclaimedWinners` at this
    /// index — never from a captured array — matching the container's existing
    /// "MUST NOT hold a second copy of view-model state" convention. If the list shrank
    /// since the modal opened (e.g. claimed on another device) and `index` is now out of
    /// range, clamp it to the last valid index; if the list is now empty, there is nothing
    /// left to page to or claim, so dismiss the modal outright (mirrors the `onDismiss`
    /// cleanup below).
    private func onPage(_ index: Int) {
        let winners = model.unclaimedWinners
        guard !winners.isEmpty else {
            model.dismissClaim()
            claimingWinner = nil
            return
        }
        let clamped = min(max(index, 0), winners.count - 1)
        claimPageIndex = clamped
        claimingWinner = winners[clamped]
    }

    /// CTA classification for `winner` (`.product`「查看獎品」/ `.discount`「立即使用」).
    /// Routed through the model so the template's public classifier
    /// (`DefaultWinClaim.awardPresentation(for:)`) is the single source — its
    /// internal `LBAwardPresentation.init(awardType:)` is not reachable here.
    /// Demo instances fall back to the same award-type rule (see `FeedWinModel`).
    private func presentation(for winner: LBWinner) -> LBAwardPresentation {
        model.presentation(for: winner)
    }

    // MARK: - Footer legal-link routing (rb-ios-win-claim-footer-links)
    //
    // The SOLE judge of "how a legal link opens" is core `LBURLOpenPolicy.decide(_:)` —
    // this container MUST NOT write a second domain rule.
    //
    // `legalLinkRoute(for:)` is split OUT as a `static`, `self`-free pure function (rather
    // than inlining its guard+switch directly into `openLegalLink`) for a concrete,
    // empirically-confirmed reason: `@State` writes performed on a `FeedWinOverlayView`
    // instance that was never actually installed by SwiftUI's renderer are silently
    // discarded (SwiftUI's own runtime behavior for un-installed `@State` — "will result in
    // a constant Binding of the initial value and will not update"; confirmed by an actual
    // failing test run, not by doc-reading). That makes `presentedLegalLink` unit-testable
    // ONLY through a real render pass, which this package has no harness for (no
    // ViewInspector; snapshot tests use `ImageRenderer`, which does not surface `.sheet`
    // content either). Pulling the actual branching decision into a pure static function
    // mirrors this file's sibling `WinClaimModalView.stage(phase:submitInFlight:result:)` —
    // a static pure engine tested directly, with the `@State` write left as an untested,
    // reviewed one-line dispatch (same split, same reason).
    //
    // `legalLinkRoute(for:)`'s inner `switch` on `LBURLOpenTarget` is EXHAUSTIVE and
    // deliberately has NO `default`: if core ever adds a target case, this MUST fail to
    // compile rather than silently fall into an existing branch (same convention as
    // `DefaultPlayerTemplate.openResolvedURL`, `url-open-host-routing-template` design.md
    // decision D). `LBLegalLinks`'s two constants are BOTH `livebuy.tv` (pinned by core's
    // `URLOpenPolicyTests`), so `.presentInApp` is the only case reachable through today's
    // two callers — `.openExternally` stays reachable only if a future caller feeds this a
    // non-livebuy string.

    /// The routing action for a raw legal-link URL string, entirely delegated to core
    /// `LBURLOpenPolicy.decide(_:)` — this function adds no domain logic of its own.
    enum LegalLinkRoute: Equatable {
        /// Present in-app (`SFSafariViewController` via `.sheet`), carrying the
        /// ALREADY-RESOLVED URL from the policy decision.
        case presentInApp(URL)
        /// Hand off to the system URL router, carrying the already-resolved URL.
        case openExternally(URL)
        /// Unopenable (`LBURLOpenPolicy.decide(_:)` returned `nil`) — safe no-op.
        case none
    }

    /// Pure: what should happen for `rawUrl`, without touching `@State` / `UIApplication`.
    static func legalLinkRoute(for rawUrl: String) -> LegalLinkRoute {
        guard let decision = LBURLOpenPolicy.decide(rawUrl) else { return .none }
        switch decision.target {
        case .inApp:
            return .presentInApp(decision.url)
        case .external:
            return .openExternally(decision.url)
        }
    }

    /// Route a raw legal-link URL string through `legalLinkRoute(for:)` and act on it.
    private func openLegalLink(_ rawUrl: String) {
        switch Self.legalLinkRoute(for: rawUrl) {
        case .presentInApp(let url):
            presentedLegalLink = url
        case .openExternally(let url):
            UIApplication.shared.open(url)
        case .none:
            break
        }
    }
}

// MARK: - Legal-link in-app presentation (rb-ios-win-claim-footer-links)
//
// A minimal SwiftUI wrapper for `SFSafariViewController`. `DefaultPlayerTemplate`
// (template layer) already uses `SFSafariViewController`, but imperatively
// (`player?.present(...)`) — that does not apply here because `FeedWinOverlayView` is a
// SwiftUI `View`, not a `UIViewController`. Grep confirmed `ios/Sources/LivebuyReferenceUI/`
// has no existing SwiftUI-native Safari wrapper to reuse, so this is a new (small, private)
// one rather than a rebuild of an existing seam.

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Identifiable conformance for sheet(item:)
//
// `LBWinner` (core model) is not `Identifiable`; `.sheet(item:)` needs it. We add
// the conformance HERE in the reference-ui layer (it does NOT modify the core
// type's source — it is an extension in the pixel layer only, and `winner.id` is
// the stable ticket id). This keeps the one-way dependency: reference-ui adds the
// presentation affordance, core stays headless.

extension LBWinner: Identifiable {}
