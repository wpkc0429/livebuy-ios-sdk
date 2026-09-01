import SwiftUI
import UIKit
import LivebuySDK
import LivebuyUI

// MARK: - PlayerShellView — family-1 player-shell container (SKELETON)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, 4 surfaces)
// Design: rb-ios-player-shell design.md D-1 / D-2 / D-7.
//
// The top-level family-1 container. It lays out the FOUR family-1 surface
// sub-views over a video area:
//
//   1. PlayerHeaderBarView    — pinned TOP        (D-2 #1, `LBPTopBar` / `LBPHostBadge`)
//   2. OperationRailView      — pinned TRAILING   (D-2 #2, `LBPSideRail`)
//   3. VideoInfoPanelView     — bottom-sheet      (D-2 #3, `LBPBottomSheet`)
//   4. LiveOverlayChromeView  — full-bleed overlay (D-2 #4, `live-chrome.jsx`)
//
// This is the SKELETON: it owns the layout + a `PlayerShellModel` + the resolved
// `ReferenceUITheme`, and composes the four surface sub-views BY TYPE NAME. The
// four sub-view TYPES are produced by the four parallel surface agents that run
// after this skeleton — see the "SUB-VIEW INPUT PATTERN" contract below, which
// every surface agent MUST implement verbatim so the container's call sites match.
//
// Until all four surface sub-views exist, this file will not compile on its own —
// that is expected (the surface agents land the types). The container's job is to
// FIX the layout + the call-site shape so the parallel agents converge.
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `Spacer` / `safeAreaInset`-free
// manual padding are all iOS-13+; no `@available` guard needed. Any surface that
// reaches for a >14 API must guard it inside its own sub-view (D-7).
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 4 parallel surface agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-1 surface sub-view is a `public struct …: View` whose initializer
// takes, IN THIS ORDER:
//
//   1. `theme: ReferenceUITheme`            — the resolved reference-ui theme
//                                             (FIRST positional argument, always).
//   2. its bound SNAPSHOT VALUE(S)          — the read-only state it renders,
//                                             passed BY VALUE from PlayerShellModel
//                                             (never the model, never the template).
//   3. optional action closures            — trailing, each defaulting to `nil`
//                                             (`onX: (() -> Void)? = nil`, etc.).
//                                             The shell does NOT own actions; the
//                                             host wires taps to core `simulate*`.
//
// Concretely, the four surface agents implement EXACTLY these initializers:
//
//   PlayerHeaderBarView(
//       theme: ReferenceUITheme,
//       title: String, hostName: String, shopLogo: String,
//       viewerCount: Int, isSubscribed: Bool, isLive: Bool,
//       onMinimize: (() -> Void)? = nil,
//       onSubscribe: (() -> Void)? = nil)
//   (top-right = a single minimize button → onMinimize; LIVE pill + viewer count
//    shown only when isLive. mute/share/info are NOT header controls.)
//
//   OperationRailView(
//       theme: ReferenceUITheme,
//       items: [LBSideRailItem], bagCount: Int, heartBurstTick: Int, muted: Bool,
//       onTapItem: ((LBSideRailKind) -> Void)? = nil)
//
//   VideoInfoPanelView(
//       theme: ReferenceUITheme,
//       info: LBInfoTabState, activeTab: LBInfoPanelTab,
//       canOpenNotice: Bool, systemNotice: String, notice: String,
//       onSelectTab: ((LBInfoPanelTab) -> Void)? = nil)
//
//   LiveOverlayChromeView(
//       theme: ReferenceUITheme,
//       announceText: String, pinnedProduct: LBProduct?,
//       hostCaption: String = "", showGestureHints: Bool = true)
//
// Rules every surface agent honours:
//   • FIRST positional arg is `theme:`. Snapshot values are passed BY VALUE.
//   • Action closures are LAST, each `… = nil` (the shell passes the host-wired
//     closure or omits it). A surface sub-view MUST render correctly with all
//     actions nil (so demo / snapshot tests construct it action-free).
//   • A surface sub-view reads ONLY its passed-in values — it MUST NOT reach back
//     into PlayerShellModel or DefaultPlayerTemplate (one-way data flow, D-1/D-4).
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available` inside the sub-view (D-7).
// ─────────────────────────────────────────────────────────────────────────────

/// The family-1 player-shell container. Drives layout for the four surface
/// sub-views over the video area; reads a `PlayerShellModel` (republished from a
/// live `DefaultPlayerTemplate` or constructed deterministically) and paints with
/// the resolved `ReferenceUITheme`.
public struct PlayerShellView: View {

    /// Minimum committed vertical drag (points) that counts as a video-switch swipe.
    /// Doubles as the `DragGesture.minimumDistance` so a tap (tiny translation) is
    /// never mistaken for a swipe and keeps firing tap-to-mute.
    private static let swipeThreshold: CGFloat = 60

    /// The republished, read-only player-shell snapshot.
    @ObservedObject public var model: PlayerShellModel

    /// The resolved reference-ui theme.
    public let theme: ReferenceUITheme

    /// Whether to paint the opaque `theme.background` placeholder behind the
    /// chrome. `true` (default) keeps snapshot baselines deterministic without a
    /// live stream. Set `false` when the shell is overlaid on a host-supplied
    /// **real video surface** (e.g. AVPlayerLayer / IVSPlayerView) — otherwise
    /// the opaque background covers the video. (See `live-chrome.jsx`: the video
    /// sits behind the chrome; the chrome itself is transparent over it.)
    public let paintsBackgroundPlaceholder: Bool

    /// Whether the info panel (bottom sheet) is currently presented. Local
    /// presentation state — the panel CONTENT (tabs / fields) is driven by the
    /// model; this only governs the sheet affordance's open/closed state.
    @State private var infoPanelPresented: Bool = false

    /// Local heart-burst trigger for the LIVE bottom bar's like tap (rb-ios-live-bottom-heart-burst).
    /// Bumped each time the user taps 愛心 → drives a `HeartBurstView` anchored above the like
    /// button (design `LBLiveBottomBar onLike → spawnHeart`). Local presentation state only.
    @State private var liveHeartTick: Int = 0

    /// The VOD products whose now-introducing cards the viewer has dismissed (by id). Each card
    /// re-appears when the playhead advances and that product re-enters `vodActiveProducts`. A
    /// Set (not a single id) so multiple simultaneously-introduced products dismiss independently
    /// (rb-ios-now-introducing-real-image-carousel, 問題 10). Local presentation state only.
    @State private var dismissedVodProductIds: Set<String> = []

    /// The LIVE pinned products the viewer has dismissed (by id) via the pinned-card close X.
    /// Each card re-appears when a DIFFERENT pinned product (different id) enters the source list
    /// (real live `narrate_status == 2` 換人 / replay timeline advancing). Mirrors the VOD
    /// `dismissedVodProductIds` per-product-id local hide (rb-ios-live-pinned-card-dismiss; parity
    /// to Android `0f6b56a5`). Local presentation state only.
    @State private var dismissedLivePinnedIds: Set<String> = []

    /// 「乾淨模式」(rb-ios-gesture-clean-mode-rewrite, design R23) — toggled by a long-press
    /// (>~0.45s) on the video area (see `scheduleCleanModeToggle`), unconditionally for both
    /// LIVE and VOD/replay (no `isLive` gate, unlike the retired `allowsHoldToPause`). `true`
    /// hides most floating chrome (§6 hide-lists) while keeping the minimize button, the
    /// expanded transport bar, and — LIVE only — the currently-narrating pinned product card.
    /// Pure呈現層 local state (design.md §1): it does NOT belong on `PlayerShellModel` and MUST
    /// NOT influence any core / view-model state.
    ///
    /// NOT reset on a video switch (design.md §1 flagged this as an apply-stage decision: no
    /// existing per-video local-state reset hook was found to piggyback on — `dismissedVodProductIds`
    /// / `dismissedLivePinnedIds` above are likewise never explicitly reset on switch, they just
    /// naturally stop matching once the new video's product ids differ. `cleanMode` has no such
    /// natural self-clearing mechanism, so carrying it across an in-place video switch is a
    /// deliberate, currently-untested edge case — not a default SwiftUI behavior this comment is
    /// merely documenting).
    ///
    /// Test-seeded via `cleanModeForTesting` on `init` (SwiftUI gestures cannot be driven from
    /// XCTest — TCC-blocked — so the chrome-hiding contract, §6, is proven by pre-seeding this
    /// state's INITIAL value before the view's first, and in the single-shot `ImageRenderer`
    /// snapshot path only, render), mirroring the existing `isScrubbingForTesting` /
    /// `scrubBarExpandedForTesting` precedent below.
    @State private var cleanMode: Bool = false

    /// Whether the「聯絡商家」confirm modal (`ContactMerchantModalView`) is presented.
    /// The rail `serviceLink` tap and the info-panel「與商家一對一對話」now present this
    /// confirm FIRST (design `contact_merchant`); only its「確定」proceeds to the existing
    /// `model.openServiceLink()` exit. Local presentation state only.
    @State private var contactMerchantPresented: Bool = false

    /// Top-right minimize → host collapses the player into the bottom-right floating
    /// preview (`FloatingWidgetView`). The shell does NOT own the collapse (it holds
    /// no `LBVideoItem`); it only forwards the intent. nil → the button is inert.
    private let onMinimize: (() -> Void)?

    /// Whether to show the gesture-hint overlay (tap-to-mute / long-press-pause /
    /// swipe). `true` (default) keeps the existing behaviour + snapshot baselines.
    /// A host that records "已顯示一次" suppresses it by passing `false` (the host owns
    /// the persisted shown flag — reference-ui only reads this boolean). Forwarded
    /// into `LiveOverlayChromeView(showGestureHints:)`.
    private let showGestureHints: Bool

    /// Tap on the video area → host-wired mute toggle (design「點擊靜音」/ "first tap
    /// unmutes"). The host wires it to the template's `toggleMute()` (→ core
    /// `setMuted`). nil → inert (demo / snapshot). This layer NEVER calls core /
    /// template mute itself; it only forwards the tap.
    private let onToggleMute: (() -> Void)?

    /// Rail「商品」(.goods) open-intent → host opens the product-list overlay
    /// (family-3 ProductSheets). The overlay composition is host-owned (the shell
    /// holds no overlay state); this only signals the intent. nil → inert.
    private let onOpenProductList: (() -> Void)?

    /// Rail「聊天」(.chat) open-intent → host shows the chat feed (family-2 FeedWin).
    /// Host-owned composition; nil → inert.
    private let onShowChatFeed: (() -> Void)?

    /// LIVE bottom-bar「留言」tap → host opens its comment composer (design
    /// `LBLiveBottomBar.onComment` opens a sheet; the real composer is the host's,
    /// already wired to `template.sendChat`). nil → the pill is inert. This is the
    /// ONE bottom-bar intent with no model forwarder; nickname / share / like / CC
    /// route through `PlayerShellModel`'s existing turnkey forwarders.
    private let onComment: (() -> Void)?

    /// 訂閱 tap (PlayerHeader 頭像徽章 + VideoInfoPanel 訂閱 pill 共用同一入口) → host-wired subscribe
    /// gate. The drop-in container wires this so an UNLOGGED-IN guest first sees the「請先登入」modal
    /// (`AuthGateModalView(.subscribe)`) instead of a silent `AUTH_REQUIRED`; a logged-in user
    /// toggles subscribe (rb-ios-subscribe-login-gate). nil (demo / snapshot / non-container) →
    /// falls back to `model.toggleSubscribe()` so those paths (and snapshot baselines) are unchanged.
    private let onSubscribe: (() -> Void)?

    /// LIVE bottom-bar 暱稱（person-edit）tap → host presents the 設定暱稱 modal. The drop-in
    /// container wires this to its local `GuestNameEditModalView` presentation (NOT the
    /// `requestGuestNameEdit()` core path, which is gated on `guestEditAvailable` and silently
    /// no-ops). nil → falls back to the existing `model.requestGuestNameEdit()` forwarder (so
    /// non-container call sites / snapshots are unchanged).
    private let onNickname: (() -> Void)?

    /// LIVE bottom-bar 分享鈕 tap. The drop-in container wires this to `context.onShare`
    /// (= `config.onShare ?? (performShare() 未被 host 攔截時 presentChannelShare)`,
    /// dropin-player-default-share-sheet / rb-ios-live-share-default-sheet), so an unwired
    /// host still gets the default system share sheet. nil → falls back to the existing
    /// headless `model.performShare()` forwarder (只派 `VIDEO_SHARE_REQUEST` 事件；非容器 /
    /// snapshot 路徑不變).
    private let onShare: (() -> Void)?

    /// Host-supplied VOD caption text (core exposes no active-caption text). Shown in
    /// the VOD branch only while `model.subtitleEnabled` and non-empty. Default "".
    private let captionText: String

    /// Optional host override for the swipe-UP gesture (「上一/下一支」switch). When
    /// non-nil, an above-threshold UP swipe calls this INSTEAD of
    /// `model.navigateToNext()`, letting a host drive video navigation from its own
    /// feed list (it owns the `LBVideoItem` list; reference-ui only exposes the
    /// gesture direction). nil (default) → falls back to the existing
    /// channel-adjacency forwarder, so every current call site is unchanged.
    private let onSwipeUp: (() -> Void)?

    /// Optional host override for the swipe-DOWN gesture. Symmetric to `onSwipeUp`:
    /// non-nil → called INSTEAD of `model.navigateToPrev()`; nil → falls back.
    private let onSwipeDown: (() -> Void)?

    /// Close-player request, fired when the user swipes toward a direction that has
    /// NO adjacent video (swipe-nav-close-on-empty #7) — only on the template-nav
    /// FALLBACK path (a host `onSwipeUp` / `onSwipeDown` override always wins and is
    /// never overridden by this). nil → the swipe-to-empty is a no-op (demo / snapshot).
    private let onCloseRequest: (() -> Void)?

    /// RETIRED (rb-ios-gesture-clean-mode-rewrite): long-press no longer drives pause/resume —
    /// it toggles `cleanMode` instead — so this closure is NEVER invoked any more (`handleDragEnded`'s
    /// `.hold` case only resets `longPressFired`). Kept (not removed) for source compatibility: any
    /// existing host that explicitly passed a non-nil closure here still compiles; it silently stops
    /// firing. Superseded by `resolveTapAction(isLive:)` + `model.togglePlayPause()` for VOD/replay
    /// pause, and by `PlaybackPausedOverlayView`'s resume button for resuming.
    @available(*, deprecated, message: "long-press no longer drives pause/resume; see resolveTapAction(isLive:) + model.togglePlayPause()")
    private let onHoldStart: (() -> Void)?

    /// RETIRED (rb-ios-gesture-clean-mode-rewrite) — see `onHoldStart`'s doc comment; never
    /// invoked any more, kept for source compatibility only.
    @available(*, deprecated, message: "long-press no longer drives pause/resume; see resolveTapAction(isLive:) + model.togglePlayPause()")
    private let onHoldEnd: (() -> Void)?

    /// Whether the on-demand chat composer (`ChatComposerBar`) is currently presented. When
    /// `true`, the LIVE bottom bar (`LiveBottomBarView` + its heart-burst sibling) is HIDDEN
    /// so the composer (which replaces the 留言 entry) does not overlap it at the bottom
    /// (rb-ios-chat-composer-opaque-hide-bottom-bar). Default `false` → bottom bar shows as
    /// before (snapshot-neutral); the drop-in container drives it from
    /// `ChatComposerController.isPresented`.
    private let composerPresented: Bool

    /// Reports the info-panel (`VideoInfoPanelView` bottom sheet) open/closed state to the
    /// container each time it changes, so the container can hide the family-2 chat feed
    /// (which sits in a HIGHER overlay layer and would otherwise occlude the sheet / swallow
    /// its taps) while the panel is up (rb-ios-info-panel-not-covered-by-chat). The info
    /// panel itself (state / 4 dismiss paths / contactMerchant) is unchanged — this is a
    /// read-only state report. nil (default / snapshot) → no report (baseline unchanged).
    private let onInfoPanelPresentedChange: ((Bool) -> Void)?

    /// Reports the LIVE/VOD mode (`model.isLive`) — its initial value and every change — to the
    /// container, so it can hide the family-2 chat feed (a LIVE-only surface whose full-bleed
    /// scrollable variant would otherwise occlude / swallow taps on the VOD side rail) while in
    /// VOD (rb-ios-hide-chat-feed-in-vod). Read-only state report. nil (default / snapshot) →
    /// no report (baseline unchanged).
    private let onIsLiveChange: ((Bool) -> Void)?

    /// Reports whether the LIVE announcement banner (`LBLiveAnnounce`) is showing —
    /// i.e. `model.announceText` non-empty — initial value + every change, so the container
    /// can give the chat feed EXTRA bottom clearance to avoid overlapping the bottom-left
    /// announcement banner when (and only when) a 公告 is present (rb-ios-live-announce-chat-
    /// clearance, 問題 4). Read-only state report. nil (default / snapshot) → no report
    /// (baseline unchanged).
    private let onHasAnnounceChange: ((Bool) -> Void)?

    /// Reports the NARROW `isScrubbing` (finger actually down) — so the container can hide the
    /// separately-composed chat feed while ACTIVELY dragging, mirroring the in-shell chrome's
    /// own `!isScrubbing` gates (rb-ios-restore-vod-playback-progress-bar, corrected post-
    /// design-review: an earlier draft mirrored the wider `scrubBarExpanded` here instead, which
    /// kept the chat feed hidden through the whole 2.8s post-release hold window instead of
    /// letting it reappear lifted — design `screens.jsx` `LBLiveChatOverlay` treats chat
    /// identically to the announce banner / pinned card: hidden only while `scrubbing`, and
    /// lifted (not hidden) while merely `scrubVisible`). Only has any effect while
    /// `usesLiveChrome` is also true (the only state where the progress bar and the chat feed
    /// can coexist — a finished-live replay, `model.isFinishedLiveReplay`); a no-op in pure VOD
    /// (chat already off) and pure live (bar never shows there). nil (default / snapshot) → no
    /// report (baseline unchanged).
    private let onScrubbingChange: ((Bool) -> Void)?

    /// Reports the WIDE `scrubBarExpanded` (touch-down through the 2.8s post-release hold) — so
    /// the container can additionally LIFT the chat feed (extra bottom inset, mirroring this
    /// view's own `scrubChromeLiftIfExpanded`) while it is visible again during the hold window
    /// (`scrubBarExpanded && !isScrubbing` — design `screens.jsx` `LBLiveChatOverlay`'s
    /// `safeBottom + (isReplay && scrubVisible ? 36 : 0)`). Same coexistence scope as
    /// [onScrubbingChange] above. nil (default / snapshot) → no report (baseline unchanged).
    private let onScrubBarExpandedChange: ((Bool) -> Void)?

    /// Reports `cleanMode` — its initial value and every change (long-press toggle) — to the
    /// container, so it can hide the family-2 chat feed (`FeedWinOverlayView`'s `ChatFeed`,
    /// which is a sibling composed by `MinimalDesign.playerOverlay`, not a descendant of this
    /// view, so `cleanMode` — a private `@State` here — cannot reach it any other way) while
    /// clean mode is on (rb-ios-clean-mode-hide-chat-feed). Read-only state report, mirrors the
    /// existing `onInfoPanelPresentedChange` / `onIsLiveChange` precedents above. nil (default /
    /// snapshot) → no report (baseline unchanged).
    private let onCleanModeChange: ((Bool) -> Void)?

    /// Test-only observability hook (rb-ios-live-double-tap-like, `docs/unit-test-discipline.md`
    /// `*ForTesting` naming): called SYNCHRONOUSLY, alongside `model.performLike()`, exactly when
    /// `registerLikeableTap()` recognizes a double-tap — reachable from BOTH `handleLiveTap()`
    /// (LIVE) and the already-ended-live-replay branch of `handleDragEnded`'s `.togglePlayPause`
    /// case (rb-ios-live-double-tap-like-replay-extend). `nil` (default, every production /
    /// non-test call site) → inert. This exists ONLY because `model.performLike()` itself has no
    /// other externally observable effect on a demo/no-template `PlayerShellModel` (`template` is a
    /// `private weak var`, always `nil` there — the same constraint
    /// `testTapDispatch_nonLiveDoesNotCallOnToggleMute`'s doc comment already notes for
    /// `togglePlayPause()`), and reading the `@State` `liveHeartTick` back is NOT reliable outside
    /// a live SwiftUI hierarchy (see `lastLikeableTapAt`'s doc comment) — mirrors the EXISTING,
    /// PROVEN-reliable `onToggleMute` closure-observability pattern used by
    /// `testTapDispatch_liveCallsOnToggleMuteNotTogglePlayPause`.
    private let performLikeForTesting: (() -> Void)?

    // MARK: - Transient gesture-feedback state (default hidden → snapshot-neutral)

    /// True once the CURRENT press has crossed the long-press threshold (`holdDelay`).
    /// Renamed from `isHolding` (rb-ios-gesture-clean-mode-rewrite, design.md §2): it no longer
    /// means "hold-to-pause is in progress" — long-press is now an EDGE-TRIGGERED toggle of
    /// `cleanMode`, not a press-and-hold state — this flag now only answers "has this gesture
    /// already fired its long-press?" for `resolveGestureEnd`'s tap/hold/swipe classification.
    /// Reset to `false` on release (`handleDragEnded`'s `.hold` case) so the NEXT press starts
    /// clean. Does NOT drive any visible overlay by itself any more (the retired
    /// `GesturePauseIconView` used to key off this; the new `PlaybackPausedOverlayView` is keyed
    /// off the REAL `model.isPlaying` instead — see `body`).
    @State private var longPressFired: Bool = false

    /// True for ~0.7s after a tap toggles mute. Drives the centre `GestureMuteToastView`.
    @State private var muteToastVisible: Bool = false

    /// Cancellable timer that promotes a sustained press into a long-press (after `holdDelay`).
    /// Cancelled if the finger moves past `moveTolerance` first (it is a swipe/scroll).
    @State private var holdWorkItem: DispatchWorkItem?

    /// Cancellable timer that auto-dismisses the mute toast after `muteToastDuration`.
    @State private var muteToastWorkItem: DispatchWorkItem?

    /// Whether a single touch's drag is in progress (prevents re-scheduling the hold on
    /// every `onChanged`; reset on `onEnded`).
    @State private var dragActive: Bool = false

    /// Wall-clock time of the most recent LIKEABLE tap — a tap landing while `model.isLive == true`
    /// OR `model.isFinishedLiveReplay == true` (renamed from `lastLiveTapAt`,
    /// rb-ios-live-double-tap-like-replay-extend: the original name became misleading once this
    /// tracker started being fed from the `.togglePlayPause` / replay branch of `handleDragEnded`
    /// too, not just the LIVE `.toggleMute` branch — see `registerLikeableTap()`). Used by
    /// `registerLikeableTap()` to detect a following double-tap within `doubleTapLikeWindow`.
    /// `nil` = no likeable tap tracked yet (or the previous one was just consumed by a recognized
    /// double-tap). NOT reset on a video switch — mirrors the existing `cleanMode` /
    /// `dismissedVodProductIds` precedent of local presentation state with no natural reset hook to
    /// piggyback on (see `cleanMode`'s doc comment); the window is only 0.32s, so the risk of a
    /// stray cross-video double-tap match is negligible.
    ///
    /// ⚠️ Like every OTHER `@State` on this SwiftUI `View` value type, a write made by ONE
    /// `handleDragEnded` call is NOT reliably observable by reading this property back — even via
    /// a SECOND, separate, purely-synchronous direct method call on the exact same `view` value
    /// held by a test outside a live SwiftUI hierarchy (empirically verified while building
    /// `rb-ios-live-double-tap-like`: two immediate, non-escaping, back-to-back
    /// `handleDragEnded(.zero)` calls did NOT recognize a double-tap — broader than, but consistent
    /// with, the escaping-closure-specific limitation `PlayerShellGestureCleanModeRewriteTests`
    /// §9.3's doc comment already documents for `cleanMode`). Tests therefore seed this via
    /// `lastLikeableTapAtForTesting` on `init` (mirrors the `cleanModeForTesting` /
    /// `isScrubbingForTesting` precedent) and drive the SINGLE call whose outcome is under test —
    /// never two separate calls expecting this to have carried a value from the first into the
    /// second.
    @State private var lastLikeableTapAt: Date?

    /// Long-press (→ `cleanMode` toggle) is recognized after this press duration (distinguishes
    /// it from a quick tap). `0.45` (rb-ios-gesture-clean-mode-rewrite, design.md §2) — aligned to
    /// `screens.jsx`'s `450`ms; was `0.3` under the retired hold-to-pause gesture.
    private static let holdDelay: TimeInterval = 0.45
    /// The mute toast auto-dismisses after this duration (issue 5: ~0.7s).
    private static let muteToastDuration: TimeInterval = 0.7
    /// Finger movement (pt) past which a pending hold is cancelled (it is a swipe/scroll).
    private static let moveTolerance: CGFloat = 12
    /// Double-tap-to-like recognition window (renamed from `liveDoubleTapWindow`,
    /// rb-ios-live-double-tap-like-replay-extend: applies to BOTH the LIVE `.toggleMute` branch and
    /// the already-ended-live-replay `.togglePlayPause` branch now — see `registerLikeableTap()`): a
    /// second likeable tap landing within this many seconds of the first counts as a double-tap.
    /// Aligned to `design/templates/minimal/screens.jsx`'s `onPointerUp` LIVE branch
    /// (`sinceLast < 320`ms). UNLIKE that web reference (which also DEFERS the single-tap
    /// mute-toggle by 300ms so a real double-tap never also flickers mute), this iOS implementation
    /// does NOT defer — see `handleLiveTap()`'s doc comment / design.md Decision 2 (of
    /// `rb-ios-live-double-tap-like`) for why (existing synchronous regression test
    /// `testTapDispatch_liveCallsOnToggleMuteNotTogglePlayPause` + a documented
    /// `@State`-across-escaping-closure testability limitation this codebase already hit for
    /// `cleanMode`). Accepted trade-off: a genuine LIVE double-tap visibly toggles mute twice in
    /// quick succession (net no permanent change, toast flickers twice) IN ADDITION to firing
    /// `performLike()` + the heart burst. The replay branch has no equivalent flicker (its single
    /// tap toggles play/pause, not mute — see `registerLikeableTap()`'s doc comment).
    private static let doubleTapLikeWindow: TimeInterval = 0.32

    // MARK: - Playback-progress scrub state (rb-ios-restore-vod-playback-progress-bar)

    /// `true` while the finger is actually down on `PlaybackProgressBarView` (touch-down…
    /// touch-up). Drives: hiding the VOD/LIVE chrome that would otherwise sit under the
    /// expanded transport bar, and (inside the bar itself) the drag-time timestamp readout.
    /// Distinct from `scrubBarExpanded` — see that property's doc comment.
    @State private var isScrubbing: Bool = false

    /// `true` from touch-down through `scrubHoldDuration` (2.8s) after touch-up. Drives the
    /// transport-bar-vs-thin-line visual AND the ~36pt bottom lift applied to chrome that has
    /// reappeared during the post-release hold window. MUST be a SEPARATE `@State` from
    /// `isScrubbing`: the design wants the transport bar (and the lifted chrome) to keep
    /// showing after release while the drag-time readout disappears immediately.
    @State private var scrubBarExpanded: Bool = false

    /// Cancellable timer that collapses `scrubBarExpanded` back to `false` `scrubHoldDuration`
    /// after the finger lifts. Re-scheduled (cancelling any pending collapse) on every new
    /// scrub start, mirroring `holdWorkItem` / `muteToastWorkItem` above.
    @State private var scrubCollapseWorkItem: DispatchWorkItem?

    /// The transport bar stays expanded this long after the finger lifts (design: 2.8s).
    private static let scrubHoldDuration: TimeInterval = 2.8
    /// The bottom lift applied to chrome that reappears during the post-release hold window, so
    /// it clears the still-expanded transport bar (design: ~36pt).
    private static let scrubChromeLift: CGFloat = 36

    /// PURE: whether `PlaybackProgressBarView` should be composed (design `screens.jsx`
    /// `LBPPlayerScreen` "Playback progress bar — VOD and replay only": `isMain && !isUpcoming
    /// && (!isLive || isReplay)`). The `isReplay` disjunct is fed `model.isFinishedLiveReplay`
    /// (`type == 3 || (type == 2 && liveStatus == 3)` — an ALREADY-ENDED live now watched back,
    /// `isLive == false` there too) — NOT the narrower core `playbackProgress.isReplay` DVR
    /// concept (a stream still actively live, `liveStatus == 1`, scrubbed behind the live edge).
    /// The two are mutually exclusive with `isLive` in incompatible ways: `isFinishedLiveReplay`
    /// can NEVER be `true` while `isLive` is `true`, so in practice this reduces to `isMain &&
    /// !isUpcoming && !isLive` — the bar shows for pure VOD and a finished-live replay, and NEVER
    /// while genuinely live (matches core's `vodScrubAllowed`, which rejects any seek while
    /// `liveStatus == 1` — a bar that showed there could visually drag but never actually seek).
    /// Kept as a literal `isReplay` PARAMETER (not simplified to a 3-arg function) for 1:1
    /// fidelity with the documented design formula; only the CALL SITE decides which flag feeds
    /// it. Unit-testable without rendering a view (rb-ios-restore-vod-playback-progress-bar).
    static func showsPlaybackProgressBar(isMain: Bool, isUpcoming: Bool, isLive: Bool, isReplay: Bool) -> Bool {
        isMain && !isUpcoming && (!isLive || isReplay)
    }

    /// The MAIN playback phase feeding `showsPlaybackProgressBar`'s `isMain` — not the intro MP4
    /// and out of the cold-start loading/splash sequence (mirrors design `screens.jsx`'s
    /// `isMain`). `isUpcoming` is passed separately to `showsPlaybackProgressBar` for 1:1
    /// fidelity with the documented formula, even though it never overlaps `introPlaying` here.
    private var isMainPlaybackPhase: Bool {
        !model.introPlaying && model.startPhase != .loading && model.startPhase != .splash
    }

    /// Whether `PlaybackProgressBarView` should be composed for the current model snapshot.
    /// Feeds `model.isFinishedLiveReplay` (已結束直播回放) as the `isReplay` disjunct — NOT
    /// `model.isReplay` (the narrower behind-live-edge-while-still-live DVR concept, which
    /// `vodScrubAllowed` would reject any seek for anyway). See the static function's doc
    /// comment.
    private var showsPlaybackProgressBar: Bool {
        Self.showsPlaybackProgressBar(isMain: isMainPlaybackPhase, isUpcoming: model.isUpcoming,
                                      isLive: model.isLive, isReplay: model.isFinishedLiveReplay)
    }

    /// The extra bottom padding (`scrubChromeLift`, ~36pt) applied to VOD chrome that has
    /// reappeared during the post-release hold window (`scrubBarExpanded && !isScrubbing`) so it
    /// clears the still-expanded transport bar; `0` at every other time (including while hidden
    /// during an active drag, where the value is moot). Mirrors the `bottomInset` passed to
    /// `LiveOverlayChromeView` for the LIVE-side equivalents.
    private var scrubChromeLiftIfExpanded: CGFloat {
        (scrubBarExpanded && !isScrubbing) ? Self.scrubChromeLift : 0
    }

    /// Touch-down on the progress bar → begin a scrub: cancel any pending collapse, mark both
    /// `isScrubbing` and `scrubBarExpanded` true, report both transitions.
    private func handleScrubStarted() {
        scrubCollapseWorkItem?.cancel()
        isScrubbing = true
        onScrubbingChange?(true)
        let wasExpanded = scrubBarExpanded
        scrubBarExpanded = true
        if !wasExpanded { onScrubBarExpandedChange?(true) }
    }

    /// Drag moved → forward the new absolute position to the EXISTING `model.seek(to:)`
    /// forwarder (no new core / view-model API; no debounce, per design).
    private func handleScrub(_ ratio: Double) {
        model.seek(to: ratio * model.duration)
    }

    /// Finger lifted → `isScrubbing` ends immediately (the readout disappears, and
    /// [onScrubbingChange] reports `false` right away so the chat feed can reappear lifted);
    /// schedule the transport bar's collapse back to the thin line after `scrubHoldDuration`
    /// ([onScrubBarExpandedChange] reports `false` only once that hold window actually ends).
    private func handleScrubEnded() {
        isScrubbing = false
        onScrubbingChange?(false)
        let work = DispatchWorkItem {
            self.scrubBarExpanded = false
            self.onScrubBarExpandedChange?(false)
        }
        scrubCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrubHoldDuration, execute: work)
    }

    /// App 進背景（`didEnterBackgroundNotification`，含觸發系統自動 PiP 的那次轉場）視同放開手指——
    /// `DragGesture` 沒有「被系統中斷」的回呼，唯一能偵測「拖曳被打斷」的訊號就是這個生命週期通知。
    /// 只在真的正在拖曳中才動作，重用既有 [handleScrubEnded] 路徑（不直接改 `scrubBarExpanded`），
    /// 讓 `onScrubbingChange` / `onScrubBarExpandedChange` 照既有時序正常回報；非拖曳中（含放開手指後
    /// 2.8 秒維持展開期間）MUST NOT 有任何可觀察副作用 (ios-scrub-reset-on-background-reference-ui)。
    ///
    /// 存取層級比照同檔案 `handleDragChanged` / `handleDragEnded`（非 `private`）——讓測試能在一個
    /// 真實建構的 struct instance 上直接同步呼叫並斷言 `onScrubbingChange` 是否觸發，而不必透過
    /// `.onReceive` 的 Combine 訂閱本身（後者是非同步、跨 escaping closure 邊界的路徑，本檔案
    /// `PlayerShellGestureCleanModeRewriteTests.swift` §9.3 已記載其在此 struct + `@State` 情境下
    /// 對測試不可觀察）；`.onReceive` 對它的接線本身以原始碼檢閱 + 全套 snapshot suite 零回歸驗證。
    func handleDidEnterBackground() {
        if isScrubbing {
            handleScrubEnded()
        }
    }

    public init(model: PlayerShellModel,
                theme: ReferenceUITheme,
                paintsBackgroundPlaceholder: Bool = true,
                showGestureHints: Bool = true,
                onMinimize: (() -> Void)? = nil,
                onToggleMute: (() -> Void)? = nil,
                onOpenProductList: (() -> Void)? = nil,
                onShowChatFeed: (() -> Void)? = nil,
                onComment: (() -> Void)? = nil,
                onSubscribe: (() -> Void)? = nil,
                onNickname: (() -> Void)? = nil,
                onShare: (() -> Void)? = nil,
                captionText: String = "",
                onSwipeUp: (() -> Void)? = nil,
                onSwipeDown: (() -> Void)? = nil,
                onCloseRequest: (() -> Void)? = nil,
                onHoldStart: (() -> Void)? = nil,
                onHoldEnd: (() -> Void)? = nil,
                composerPresented: Bool = false,
                onInfoPanelPresentedChange: ((Bool) -> Void)? = nil,
                onIsLiveChange: ((Bool) -> Void)? = nil,
                onHasAnnounceChange: ((Bool) -> Void)? = nil,
                onScrubbingChange: ((Bool) -> Void)? = nil,
                onScrubBarExpandedChange: ((Bool) -> Void)? = nil,
                onCleanModeChange: ((Bool) -> Void)? = nil,
                isScrubbingForTesting: Bool = false,
                scrubBarExpandedForTesting: Bool = false,
                cleanModeForTesting: Bool = false,
                lastLikeableTapAtForTesting: Date? = nil,
                performLikeForTesting: (() -> Void)? = nil) {
        self.model = model
        self.theme = theme
        self.paintsBackgroundPlaceholder = paintsBackgroundPlaceholder
        self.showGestureHints = showGestureHints
        self.onMinimize = onMinimize
        self.onToggleMute = onToggleMute
        self.onOpenProductList = onOpenProductList
        self.onShowChatFeed = onShowChatFeed
        self.onComment = onComment
        self.onSubscribe = onSubscribe
        self.onNickname = onNickname
        self.onShare = onShare
        self.captionText = captionText
        self.onSwipeUp = onSwipeUp
        self.onSwipeDown = onSwipeDown
        self.onCloseRequest = onCloseRequest
        self.onHoldStart = onHoldStart
        self.onHoldEnd = onHoldEnd
        self.composerPresented = composerPresented
        self.onInfoPanelPresentedChange = onInfoPanelPresentedChange
        self.onIsLiveChange = onIsLiveChange
        self.onHasAnnounceChange = onHasAnnounceChange
        self.onScrubbingChange = onScrubbingChange
        self.onScrubBarExpandedChange = onScrubBarExpandedChange
        self.onCleanModeChange = onCleanModeChange
        self.performLikeForTesting = performLikeForTesting
        // Test-only seed for the two scrub-driven `@State` properties (see their doc comments
        // below) — there is no production gesture-simulation path to reach these states in a
        // synchronous snapshot render, so `PlayerShellPlaybackProgressBarSnapshotTests` seeds them
        // directly via this initializer (docs/unit-test-discipline.md `*ForTesting` naming).
        _isScrubbing = State(initialValue: isScrubbingForTesting)
        _scrubBarExpanded = State(initialValue: scrubBarExpandedForTesting)
        // Test-only seed for `cleanMode` (rb-ios-gesture-clean-mode-rewrite §6 chrome-hiding
        // contract) — same rationale as the two scrub seeds directly above.
        _cleanMode = State(initialValue: cleanModeForTesting)
        // Test-only seed for `lastLikeableTapAt` (rb-ios-live-double-tap-like; parameter renamed in
        // rb-ios-live-double-tap-like-replay-extend) — same rationale: lets a test simulate "a
        // first likeable tap already happened Δt ago" and drive the SINGLE `handleDragEnded` call
        // under test, without depending on `@State` carrying a value from one call into a separate
        // one (see `lastLikeableTapAt`'s doc comment for why that is NOT reliable outside a live
        // SwiftUI hierarchy).
        _lastLikeableTapAt = State(initialValue: lastLikeableTapAtForTesting)
    }

    /// Resolves a committed vertical drag into the correct video-switch action,
    /// honoring optional host overrides. Called verbatim by the swipe gesture's
    /// `.onEnded`; extracted (`internal`) so the override-vs-fallback dispatch is
    /// unit-testable without rendering a SwiftUI gesture (per unit-test discipline).
    ///
    /// The fallback (no host override) swipe-nav action (swipe-nav-close-on-empty #7).
    enum SwipeNavAction: Equatable { case navigateNext, navigatePrev, close, none }

    /// PURE: resolve a committed vertical drag (no host override) into the template-nav
    /// fallback action. A swipe toward a direction WITH an adjacent video navigates; a
    /// swipe toward a direction with NO video → `.close` (close the player); below the
    /// threshold → `.none`. Unit-testable without rendering a gesture.
    static func resolveSwipeNav(translationHeight dy: CGFloat, hasNext: Bool, hasPrev: Bool) -> SwipeNavAction {
        if dy <= -swipeThreshold { return hasNext ? .navigateNext : .close }
        if dy >= swipeThreshold { return hasPrev ? .navigatePrev : .close }
        return .none
    }

    /// PURE: whether a vertical swipe is allowed to trigger a video-switch / close action.
    /// **直播正在進行中**（`isLive`, `liveStatus == 1`，涵蓋「串流直播」與「預錄直播」兩者，與
    /// `isUpcoming` / `isFinishedLiveReplay` 互斥）MUST NOT 用垂直滑動切換影片（design R18，
    /// `screens.jsx` 的 `liveInProgress = effectiveState === 'live_main' && !isUpcoming && !isReplay`）；
    /// 預告倒數（upcoming）與已結束直播的回放（finished-live replay）不受影響，維持可滑動換片
    /// （rb-ios-live-swipe-gesture-gating）。抽成純函式使此 gate 可單元測試（不需渲染手勢）。
    static func allowsSwipeNav(isLive: Bool) -> Bool { !isLive }

    /// Resolves a committed vertical drag into the correct action, honoring host overrides.
    /// - **直播進行中**（`model.isLive == true`）MUST NOT 觸發任何換片 / 關閉動作——本函式整個提早
    ///   return，host override（`onSwipeUp`/`onSwipeDown`）、model fallback（`navigateToNext`/
    ///   `navigateToPrev`）、close-on-empty（`onCloseRequest`）三者皆不觸發（rb-ios-live-swipe-
    ///   gesture-gating）。拖曳事件本身仍由呼叫端（`resolveGestureEnd`）分類為 swipe，不會落回 tap，
    ///   故仍被手勢層吞掉，不會誤觸點擊靜音。
    /// - A host `onSwipeUp` / `onSwipeDown` override ALWAYS wins (called instead of any
    ///   template-nav / close behavior).
    /// - Otherwise (template-nav fallback): swipe toward a video → navigate; swipe toward
    ///   an EMPTY direction (no next / no prev) → `onCloseRequest()` (close the player, #7).
    func handleSwipeEnded(translationHeight dy: CGFloat) {
        // 直播進行中：不換片、不關閉（拖曳事件已由呼叫端分類為 swipe，仍算被吞掉，只是無 side effect）。
        guard Self.allowsSwipeNav(isLive: model.isLive) else { return }
        // Host override wins, regardless of next/prev availability.
        if dy <= -Self.swipeThreshold, let onSwipeUp = onSwipeUp { onSwipeUp(); return }
        if dy >= Self.swipeThreshold, let onSwipeDown = onSwipeDown { onSwipeDown(); return }
        // Fallback: template-nav, closing when there is no video in that direction.
        switch Self.resolveSwipeNav(translationHeight: dy,
                                    hasNext: model.hasNextVideo, hasPrev: model.hasPrevVideo) {
        case .navigateNext: model.navigateToNext()
        case .navigatePrev: model.navigateToPrev()
        case .close:        onCloseRequest?()
        case .none:         break
        }
    }

    // MARK: - Consolidated tap / hold / swipe gesture (single DragGesture(minimumDistance: 0))

    /// The classification of a finished video-area gesture. Extracted as a PURE function
    /// (`resolveGestureEnd`) so the tap-vs-swipe-vs-hold dispatch is unit-testable without
    /// rendering a SwiftUI gesture (unit-test discipline).
    enum GestureOutcome: Equatable { case hold, swipeUp, swipeDown, tap }

    /// Classify a finished gesture: a recognized long-press wins; else a committed vertical
    /// drag is a swipe (up = next, down = prev); else (quick, small translation) a tap. The
    /// `isHolding` parameter label is UNCHANGED (design.md §2: renaming it is cosmetic, not
    /// mandatory — kept verbatim to avoid churning every existing call site) but its SEMANTICS
    /// changed (rb-ios-gesture-clean-mode-rewrite): it now answers "has this gesture already
    /// crossed the long-press threshold" (fed `longPressFired` at the call site), not "is a
    /// hold-to-pause currently in progress".
    static func resolveGestureEnd(isHolding: Bool, translationHeight dy: CGFloat) -> GestureOutcome {
        if isHolding { return .hold }
        if dy <= -swipeThreshold { return .swipeUp }
        if dy >= swipeThreshold { return .swipeDown }
        return .tap
    }

    /// The video-area single-tap action (rb-ios-gesture-clean-mode-rewrite, design R23,
    /// supersedes the prior unconditional tap-to-mute). Single decision point for the `.tap`
    /// branch of `handleDragEnded`.
    enum TapAction: Equatable { case toggleMute, togglePlayPause }

    /// PURE: resolve the single-tap action for the current mode. 進行中直播（`isLive`,
    /// `liveStatus == 1`, 涵蓋串流直播與預錄直播）單擊維持切換靜音；VOD／已結束直播的回放／直播
    /// 預告倒數（皆 `isLive == false`）單擊改為切換播放/暫停 —— 這使得進行中直播事實上無法被單擊
    /// 手勢暫停（分流後自然沒有可觸達暫停/播放的入口，效果等同已退役的 `allowsHoldToPause` 抑制，
    /// 但不再是對某個獨立手勢的顯式抑制）。抽成純函式使此決策可單元測試（不需渲染手勢）。
    static func resolveTapAction(isLive: Bool) -> TapAction {
        isLive ? .toggleMute : .togglePlayPause
    }

    /// PURE: whether a likeable tap ending `elapsed` seconds after the previous tracked likeable
    /// tap counts as a double-tap (renamed from `isLiveDoubleTap`,
    /// rb-ios-live-double-tap-like-replay-extend: the original name became misleading once this
    /// same decision started being consulted from the already-ended-live-replay branch of
    /// `handleDragEnded` too, not just the LIVE branch — see `registerLikeableTap()`) — i.e. it
    /// should ALSO fire `performLike()` + the heart burst, on top of whatever the tap's own action
    /// already does (LIVE: unconditional mute-toggle via `handleLiveTap()`; already-ended-live
    /// replay: `model.togglePlayPause()`). `elapsed == nil` (no likeable tap tracked yet, or the
    /// tracker was just consumed by a previously-recognized double-tap) is never a double-tap.
    /// Extracted (unit-test discipline, mirrors `resolveTapAction` / `cleanModeAfterLongPress`
    /// above) so the timing boundary is directly testable with synthetic elapsed values — no real
    /// clock / timer / rendered gesture required.
    static func isDoubleTapLikeHit(elapsedSinceLastLikeableTap elapsed: TimeInterval?, window: TimeInterval) -> Bool {
        guard let elapsed = elapsed else { return false }
        return elapsed <= window
    }

    /// PURE: the new `cleanMode` value after a recognized long-press, given the CURRENT value.
    /// Encodes the "edge-triggered TOGGLE, not press-and-hold / not always-set-to-true" design
    /// decision (design.md §2) as a directly unit-testable unit, mirroring `resolveTapAction`
    /// above. `scheduleCleanModeToggle`'s timer closure calls this rather than inlining
    /// `.toggle()` so the semantic is independently testable — `@State` mutated from inside an
    /// escaping `DispatchWorkItem` closure cannot itself be observed by a test driving the view
    /// outside a live SwiftUI hierarchy (the closure captures a value-type snapshot of `self`),
    /// so this pure half of the decision is the unit-testable surface for that behavior.
    static func cleanModeAfterLongPress(current: Bool) -> Bool { !current }

    /// Drag in progress: on the first change schedule the long-press timer; if the finger moves
    /// past `moveTolerance` before it fires, cancel the pending long-press (it is a swipe/scroll,
    /// not a long-press) so `cleanMode` never toggles on a swipe.
    ///
    /// Extracted (`internal`, not `private`) so the schedule/cancel dispatch is directly
    /// unit-testable without rendering a SwiftUI gesture — mirrors the EXISTING
    /// `handleSwipeEnded` precedent (its own doc comment: "extracted so the ... dispatch is
    /// unit-testable without rendering a SwiftUI gesture").
    func handleDragChanged(_ translation: CGSize) {
        if !dragActive {
            dragActive = true
            scheduleCleanModeToggle()
        }
        if !longPressFired,
           abs(translation.width) > Self.moveTolerance || abs(translation.height) > Self.moveTolerance {
            cancelPendingHold()
        }
    }

    /// Drag ended: classify and dispatch. Long-press → already toggled `cleanMode` when the
    /// timer fired (design.md §2: edge-triggered, NOT press-and-hold) — release only resets the
    /// classification flag for the next gesture, it does NOT call `onHoldStart`/`onHoldEnd`
    /// (retired, rb-ios-gesture-clean-mode-rewrite). Swipe → existing `handleSwipeEnded`. Tap →
    /// `resolveTapAction(isLive:)` picks mute-toggle (+ toast) vs `model.togglePlayPause()` — this
    /// single-tap ACTION dispatch is unchanged by rb-ios-live-double-tap-like-replay-extend.
    /// `.togglePlayPause` additionally registers a likeable tap when the video is an already-ended
    /// live replay (`model.isFinishedLiveReplay == true`) — see `registerLikeableTap()`'s doc
    /// comment. Pure VOD (`isFinishedLiveReplay == false`) never calls it, unchanged from before
    /// this extension.
    ///
    /// Extracted (`internal`, not `private`) — same rationale as `handleDragChanged` above.
    func handleDragEnded(_ translation: CGSize) {
        cancelPendingHold()
        switch Self.resolveGestureEnd(isHolding: longPressFired, translationHeight: translation.height) {
        case .hold:
            longPressFired = false
        case .swipeUp, .swipeDown:
            handleSwipeEnded(translationHeight: translation.height)
        case .tap:
            switch Self.resolveTapAction(isLive: model.isLive) {
            case .toggleMute:
                handleLiveTap()
            case .togglePlayPause:
                model.togglePlayPause()
                // rb-ios-live-double-tap-like-replay-extend: already-ended-live replay ALSO gets
                // double-tap-to-like, layered on top of the unchanged single-tap
                // togglePlayPause() above. Pure VOD (isFinishedLiveReplay == false) is excluded,
                // unchanged from rb-ios-live-double-tap-like. Reaching this branch already implies
                // model.isLive == false (resolveTapAction's own contract), so this reduces to
                // exactly the `usesLiveChrome` formula (`isLive || isFinishedLiveReplay`) without
                // needing to reference that private var here.
                if model.isFinishedLiveReplay {
                    registerLikeableTap()
                }
            }
        }
        dragActive = false
    }

    /// Schedule the long-press promotion: after `holdDelay` (~0.45s) of a sustained press,
    /// toggle `cleanMode` ONCE (rb-ios-gesture-clean-mode-rewrite, design.md §2 — renamed from
    /// `scheduleHold`). Unlike the retired `scheduleHold`, this has NO `isLive` guard: clean
    /// mode applies unconditionally to both LIVE and VOD/replay (the retired
    /// `allowsHoldToPause(isLive:)` gate is fully removed, not merely bypassed). Cancelled by
    /// movement or release first (`cancelPendingHold`).
    private func scheduleCleanModeToggle() {
        let work = DispatchWorkItem {
            self.longPressFired = true
            self.cleanMode = Self.cleanModeAfterLongPress(current: self.cleanMode)
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
    }

    /// Cancel a pending (not-yet-fired) hold timer.
    private func cancelPendingHold() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }

    /// Show the centre mute toast and auto-dismiss it after `muteToastDuration` (~0.7s).
    private func showMuteToast() {
        muteToastWorkItem?.cancel()
        muteToastVisible = true
        let work = DispatchWorkItem { self.muteToastVisible = false }
        muteToastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.muteToastDuration, execute: work)
    }

    /// LIVE video-area tap dispatch (rb-ios-live-double-tap-like). The existing unconditional
    /// mute-toggle + toast fires on EVERY LIVE tap — SYNCHRONOUSLY, unchanged from before this
    /// change — so `testTapDispatch_liveCallsOnToggleMuteNotTogglePlayPause` keeps passing
    /// untouched. Additionally (not instead), `registerLikeableTap()` layers the double-tap-to-like
    /// judgment on top (rb-ios-live-double-tap-like-replay-extend extracted that judgment into a
    /// method shared with the already-ended-live-replay branch of `handleDragEnded` — see its doc
    /// comment; this method's own LIVE-specific behavior, the unconditional mute-toggle + toast, is
    /// unchanged).
    ///
    /// Deliberately does NOT defer the mute-toggle the way
    /// `design/templates/minimal/screens.jsx`'s `onPointerUp` LIVE branch does (300ms `setTimeout`
    /// before committing to a single tap) — see `rb-ios-live-double-tap-like`'s design.md
    /// Decision 2. Two independent reasons: (1) the existing synchronous regression test above
    /// would break; (2) deferring would need an escaping `DispatchWorkItem` mutating `@State`,
    /// which this exact test file's own §9.3 comment already documents as UNOBSERVABLE by a test
    /// holding a `PlayerShellView` value outside a live SwiftUI hierarchy (proven empirically for
    /// `cleanMode` / `scheduleCleanModeToggle`). Accepted trade-off: a genuine rapid double-tap
    /// visibly toggles mute twice (net no permanent change, toast flickers twice) IN ADDITION to
    /// firing the like.
    private func handleLiveTap() {
        onToggleMute?()
        showMuteToast()
        registerLikeableTap()
    }

    /// Shared double-tap-to-like bookkeeping (extracted from `handleLiveTap()`,
    /// rb-ios-live-double-tap-like-replay-extend): compares this tap's time against
    /// `lastLikeableTapAt`, and on a hit within `doubleTapLikeWindow`, fires
    /// `model.performLike()` + bumps `liveHeartTick` (the SAME heart-burst path the LIVE bottom
    /// bar's like button already uses, `rb-ios-live-bottom-heart-burst`) — this is layered ON TOP
    /// OF, never instead of, whatever the tap's own single-tap action already did. Called from TWO
    /// sites in `handleDragEnded`: `handleLiveTap()` (LIVE, after the unconditional
    /// `onToggleMute?()` + `showMuteToast()`) and the `.tap` → `.togglePlayPause` branch, gated at
    /// that call site on `model.isFinishedLiveReplay` (already-ended live replay only — pure VOD
    /// never reaches this method). Extracting this once avoids duplicating the time-window compare
    /// + side-effect triplet across both call sites.
    ///
    /// Every mutation here is SYNCHRONOUS (no escaping closure captures `self`) — but unlike a
    /// plain stored closure (e.g. `onToggleMute`), `@State` such as `lastLikeableTapAt` /
    /// `liveHeartTick` is NOT reliably carried from one top-level `handleDragEnded` call into a
    /// SEPARATE, later one when this view is not installed in a live SwiftUI hierarchy (see
    /// `lastLikeableTapAt`'s doc comment) — hence `performLikeForTesting` for observability, and
    /// `lastLikeableTapAtForTesting` on `init` for seeding, so tests only ever need to drive ONE
    /// call.
    private func registerLikeableTap() {
        let now = Date()
        let elapsed = lastLikeableTapAt.map { now.timeIntervalSince($0) }
        if Self.isDoubleTapLikeHit(elapsedSinceLastLikeableTap: elapsed, window: Self.doubleTapLikeWindow) {
            // Consumed: a THIRD rapid tap starts a fresh pairing rather than chaining into a
            // string of likes.
            lastLikeableTapAt = nil
            model.performLike()
            liveHeartTick &+= 1
            performLikeForTesting?()
        } else {
            lastLikeableTapAt = now
        }
    }

    // MARK: - Chrome gating (rb-ios-intro-chrome-minimal)

    /// live-chrome 家族 — 真直播（`isLive`，`liveStatus == 1`）或回放（`isFinishedLiveReplay`，
    /// 已結束的直播 `type == 2 && liveStatus == 3`）。兩者套用相同的 LIVE 版型（LIVE 疊層 chrome +
    /// LIVE 底部 bar + 聊天 feed）；純 VOD 點播（兩旗標皆 false）走 VOD 版型（side rail + 浮動袋 +
    /// now-introducing 輪播）。回放版型對齊直播當下（rb-ios-replay-live-chrome）。
    private var usesLiveChrome: Bool {
        model.isLive || model.isFinishedLiveReplay
    }

    /// The VOD main-chrome family — NOT live-chrome 家族（LIVE / 回放）/ upcoming(awaitingLive) /
    /// upcoming-intro. 純 VOD side rail + floating bag + (in the main state) header live here.
    private var isVodMainChrome: Bool {
        !usesLiveChrome && !model.isUpcoming && !model.introPlaying
    }

    /// Whether the VOD MAIN chrome (side rail + floating bag) should show. Only the
    /// OPENING sequence suppresses it — the full-screen brand loader (`.loading`) and
    /// the intro MP4 (`.splash`). From `.buffering` onward it shows (design `showMainChrome`
    /// only hides the opening loader / intro, not the main-stream buffering). For a
    /// no-intro VOD (the common case) there is no intro MP4, so by `.buffering` the channel
    /// is already loaded (rail enablement set, header data filled) — the rail/bag appear
    /// alongside the header instead of waiting for the first played frame (`.done`).
    /// This single source of truth drives the rail, the floating bag, AND the
    /// now-introducing card's bag-clearance inset (rb-ios-vod-rail-show-on-buffering).
    private var showsVodMainChrome: Bool {
        isVodMainChrome && model.startPhase != .loading && model.startPhase != .splash
    }

    /// 右下角浮動商品袋（`FloatingBagButtonView`，48×48 + trailing 12）佔據的右側淨寬（pt）：
    /// trailing 12 + 袋 48 + 8 間隙 = 68。VOD「正在介紹」卡在浮動袋存在時，trailing 以此量內縮
    /// （往左縮短）避讓浮動袋，浮動袋本身不動（rb-ios-vod-now-introducing-no-bag-overlap）。
    private static let floatingBagClearance: CGFloat = 68

    public var body: some View {
        ZStack {
            // The video area sits behind everything (host supplies the actual
            // video surface; the shell paints the themed background placeholder so
            // snapshot baselines are deterministic without a live stream). When
            // overlaid on a real video surface, skip it so the video shows.
            //
            // Upcoming (直播預告 awaitingLive) wears the LIVE chrome (design screens.jsx:
            // upcoming is in the live-chrome family). Its background is the
            // UpcomingCountdownView (cover + dark mask + date + big time) — promoted from
            // a top-most moment to the shell background, like design `LBLiveUpcomingOverlay`.
            // `live:` loads the cover only when a real video surface is present
            // (placeholder suppressed); the snapshot path stays the deterministic pure-color
            // background. This branch REPLACES the plain placeholder background.
            if model.isUpcoming {
                UpcomingCountdownView(
                    theme: theme,
                    scheduledStartAt: model.upcomingStartAt,
                    live: !paintsBackgroundPlaceholder,
                    coverUrl: model.upcomingCover)
                    .ignoresSafeAreaCompat()
            } else if paintsBackgroundPlaceholder {
                theme.background
                    .ignoresSafeAreaCompat()
            }

            // Tap-to-unmute gesture over the video area (design「點擊靜音」/ "first tap
            // unmutes"). A transparent, full-bleed tap target placed BELOW the chrome
            // controls so header / rail / info-panel / pinned-card taps win; only
            // empty video-area taps fire onToggleMute (host → template.toggleMute()).
            // Color.clear + contentShape = no pixels → snapshot baselines unchanged;
            // inert when onToggleMute == nil (demo / snapshot).
            // Vertical-swipe-to-switch-video (design hint「上下滑動 = 切換影片」). Attached
            // via `.simultaneousGesture` so it COMPOSES with the tap-to-mute above:
            // a tap (small translation) fires onToggleMute; a committed vertical drag
            // past the threshold fires navigation. swipe-UP (height ≤ -threshold) ⇒
            // next video; swipe-DOWN (height ≥ +threshold) ⇒ previous. A below-
            // threshold drag is a no-op (fire on .onEnded, not .onChanged).
            //
            // Host override: if the host injects `onSwipeUp` / `onSwipeDown`, that
            // closure is called INSTEAD of the model forwarder (the host then drives
            // navigation from its own feed list). When nil (default — all demo /
            // snapshot / existing call sites), it falls back to the model forwarders,
            // which no-op when there is no adjacent video / no bound template, so
            // demo / snapshot instances never crash. Invisible → pixel-neutral.
            // ONE DragGesture(minimumDistance: 0) resolves tap / hold / swipe from a single
            // touch (avoids the SwiftUI tap-vs-drag arbitration race): onChanged schedules a
            // cancellable hold timer (cancelled by movement); onEnded classifies via
            // `resolveGestureEnd` → tap (mute + toast) / swipe (handleSwipeEnded) / hold (resume).
            // INVARIANT (design screens.jsx: main gesture layer is `inset:0`): this gesture
            // layer is full-bleed and must stay reachable across the WHOLE screen, incl. the
            // upper half. It sits LOW in the ZStack, so any decorative full/half-bleed overlay
            // ABOVE it MUST be non-interactive (`allowsHitTesting(false)`) or it swallows the
            // empty-area taps before they reach here (the header scrim gradient was the offender
            // — see PlayerHeaderBarView). Genuinely-interactive controls (header buttons / rail /
            // bottom bar / pinned card) hit-test only their own content, so empty-area taps still
            // fall through to this layer.
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in handleDragChanged(value.translation) }
                        .onEnded { value in handleDragEnded(value.translation) }
                )
                .accessibilityIdentifier(LBAccessibilityID.playerVideoSurface)

            // Mode-branched chrome (design screens.jsx「VOD vs LIVE switches here」):
            //   UPCOMING → nothing drawn here (the UpcomingCountdownView background IS the
            //          surface; no live overlay / no VOD mini-cart / no announce-pinned-chat).
            //   LIVE → the live overlay chrome (announce / pinned card / host caption
            //          / floating gesture hints). `PlaybackProgressBarView` (composed further
            //          below, as an independent top-level sibling) additionally overlays this
            //          branch ONLY when the stream is a finished-live replay
            //          (`model.isFinishedLiveReplay`, `isLive == false` there too) — NEVER while
            //          genuinely live (rb-ios-restore-vod-playback-progress-bar).
            //   VOD  → the currently-introduced product card (MiniCartView bound to
            //          model.vodActiveProduct, bottom-leading) + the CC caption line
            //          when subtitles are on + `PlaybackProgressBarView`. The live chat /
            //          pinned / announce / host-caption are NOT drawn for VOD.
            if model.isUpcoming || model.introPlaying {
                // upcoming awaitingLive OR the upcoming intro is playing → no live-overlay
                // chrome (announce / pinned / chat / host-caption don't exist pre-live).
                EmptyView()
            } else if usesLiveChrome {
                LiveOverlayChromeView(
                    theme: theme,
                    // 拖曳播放進度條期間（isScrubbing）隱藏公告 banner，讓出畫面給 transport bar
                    // （rb-ios-restore-vod-playback-progress-bar；只在 usesLiveChrome 與進度條同時
                    // 出現的「已結束直播回放」狀態下才有實際效果——純直播進行中進度條本不顯示，
                    // 即使已被拖到 live edge 之後〔model.isReplay〕也不顯示，見 showsPlaybackProgressBar
                    // 的文件註解）。
                    announceText: isScrubbing ? "" : model.announceText,
                    // 釘選卡來源依真直播 vs 回放分流（rb-ios-replay-live-chrome）：
                    //   真直播 → livePinnedProducts（多件 narrate_status==2 輪播 + 分頁點；空時
                    //            fallback 單一 activeProduct ?? first isHot，問題 7）。
                    //   回放   → vodActiveProducts（時間軸窗格 [beginTime,endTime) 含 playhead，隨
                    //            播放進度更新；回放無即時 narrate_status==2，改用後端介紹時間窗）。
                    // 先算來源分支、再以本地 dismiss set 過濾（涵蓋真直播 / 回放兩分支），使 close X
                    // 逐商品本地隱藏（rb-ios-live-pinned-card-dismiss，鏡像 VOD dismissedVodProductIds）。
                    // 拖曳播放進度條期間同樣清空（見上 announceText 的理由）。
                    pinnedProducts: isScrubbing ? [] : LiveOverlayChromeView.visiblePinnedProducts(
                        model.isLive ? model.livePinnedProducts : model.vodActiveProducts,
                        dismissedIds: dismissedLivePinnedIds),
                    // 放開手指到 2.8 秒收回這段期間（scrubBarExpanded && !isScrubbing），釘選卡 /
                    // 公告 banner 重新出現時上移，讓出底部 transport bar 空間
                    // （rb-ios-restore-vod-playback-progress-bar）。預設 0 對既有呼叫點無影響。
                    bottomInset: (scrubBarExpanded && !isScrubbing) ? Self.scrubChromeLift : 0,
                    // Real product image on the pinned card only over a live video surface
                    // (placeholder suppressed) — same gate as the shop logo / VOD card
                    // (live-pinned-card-image-radius). Snapshot/demo keeps the placeholder.
                    live: !paintsBackgroundPlaceholder,
                    // Host-suppressible: a host that has already shown the hint once
                    // passes showGestureHints: false (it owns the persisted flag).
                    showGestureHints: showGestureHints,
                    // 長按提示的 per-line `!model.isLive` gate 已退役（rb-ios-gesture-clean-mode-
                    // rewrite，取代 rb-ios-live-hold-pause-suppress）：`showsHoldPauseHint` 恆傳
                    // true（省略吃預設值即可）——乾淨模式提示不分直播/VOD 皆該顯示，只受整體
                    // `showGestureHints` 控制。
                    // 點擊提示文案改依 `model.isLive` 分流（單擊分流的同一組語意，見
                    // `resolveTapAction(isLive:)`）。
                    isLive: model.isLive,
                    // Real video overlay (placeholder bg suppressed) → fade the gesture
                    // hints; standalone / snapshot keeps them static (deterministic).
                    autoFadeGestureHints: !paintsBackgroundPlaceholder,
                    // 乾淨模式（rb-ios-gesture-clean-mode-rewrite ADDED Requirement）：隱藏 announce
                    // banner / host caption / 手勢提示，MUST NOT 影響釘選商品卡（見
                    // `LiveOverlayChromeView.cleanMode` 的內部 gate 範圍）。
                    cleanMode: cleanMode,
                    // Pinned-product card tap → turnkey product-detail default flow.
                    onTapPinnedProduct: { product in model.performProductTap(product) },
                    // 釘選卡 close X → 逐商品本地隱藏（把 id 加入本地 dismissedLivePinnedIds，
                    // 下次過濾即不再餵入該卡；鏡像 VOD onDismiss，rb-ios-live-pinned-card-dismiss）。
                    onDismissPinnedProduct: { id in dismissedLivePinnedIds.insert(id) },
                    // 公告橫幅 tap → 切到 VideoInfoPanel 公告分頁並開啟資訊面板（重用 host badge tap
                    // 的同一 infoPanelPresented 狀態）。公告顯示中 ⇒ notice 非空 ⇒ canOpenNotice
                    // ⇒ selectInfoTab(.notice) 生效（live-announce-tap-open-info-panel，問題 2）。
                    onTapAnnounce: {
                        model.selectInfoTab(.notice)
                        withAnimation { infoPanelPresented = true }
                    })
            } else {
                // 拖曳播放進度條期間（isScrubbing）隱藏字幕疊層 / 介紹中商品卡輪播，讓出畫面給
                // transport bar；放開手指到 2.8 秒收回這段期間（scrubBarExpanded &&
                // !isScrubbing）兩者重新出現並上移，讓出底部 transport bar 空間
                // （rb-ios-restore-vod-playback-progress-bar）。
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    // CC 字幕 overlay 在乾淨模式隱藏（rb-ios-gesture-clean-mode-rewrite ADDED
                    // Requirement「…長按切換「乾淨模式」隱藏懸浮 chrome」VOD 隱藏清單）。
                    //
                    // 字幕來源兩層 fallback（rb-ios-subtitle-vtt-caption-display）：host 明確傳入的
                    // `captionText`（既有參數）優先，維持既有 host-override 行為 100% 不變；
                    // `captionText` 為空才 fallback 到 `model.subtitleCues`（turnkey 容器抓取 +
                    // 解析 `channel.subtitle_url` 灌入）在目前 `model.position` 命中的 cue 文字。
                    let effectiveCaption = captionText.isEmpty
                        ? (VTTSubtitleParser.activeCue(model.subtitleCues, at: model.position)?.text ?? "")
                        : captionText
                    if model.subtitleEnabled && !effectiveCaption.isEmpty && !isScrubbing && !cleanMode {
                        CaptionOverlayView(theme: theme, text: effectiveCaption)
                            .padding(.bottom, 8 + scrubChromeLiftIfExpanded)
                    }
                    // VOD now-introducing products: a full-width card carousel (real image + page
                    // dots + swipe) over ALL products whose [beginTime,endTime) window contains
                    // the playhead (`model.vodActiveProducts`), minus the ones dismissed locally.
                    // rb-ios-now-introducing-real-image-carousel (問題 9 滿寬+真實圖, 問題 10 多商品輪播).
                    // 「mini-cart」（design `LBPMiniCart`）在乾淨模式隱藏 — iOS 對應此 now-introducing
                    // carousel（rb-ios-gesture-clean-mode-rewrite ADDED Requirement）。
                    let introducing = model.vodActiveProducts
                        .filter { !dismissedVodProductIds.contains($0.id) }
                    if !introducing.isEmpty && !isScrubbing && !cleanMode {
                        NowIntroducingCarouselView(
                            theme: theme,
                            peeks: introducing.map { product in
                                LBMiniCartPeek(
                                    productId: product.id,
                                    name: product.name,
                                    priceShow: product.priceShow,
                                    soldOut: product.soldOut,
                                    pic: product.photos.first ?? product.pic)
                            },
                            // Real image only over a live video surface (placeholder suppressed);
                            // the snapshot path keeps the deterministic placeholder.
                            live: !paintsBackgroundPlaceholder,
                            onDismiss: { id in dismissedVodProductIds.insert(id) },
                            onOpenDetail: { id in
                                if let product = introducing.first(where: { $0.id == id }) {
                                    model.performProductTap(product)
                                }
                            })
                            // 往左佔滿；但在浮動商品袋顯示時（showsVodMainChrome，即 VOD 且
                            // startPhase ∈ {.buffering, .done}），trailing 內縮讓出浮動袋的右側空間，
                            // 避免卡片右下角與袋重疊（rb-ios-vod-now-introducing-no-bag-overlap）。
                            // 開場序列（.loading / .splash）無袋 → 維持 8（避讓跟隨浮動袋顯示時機）。
                            .padding(.leading, 8)
                            .padding(.trailing, showsVodMainChrome ? Self.floatingBagClearance : 8)
                            .padding(.bottom, 12 + scrubChromeLiftIfExpanded)
                    }
                }
            }

            // Top bar pinned top, side rail pinned trailing. Surfaces 1 + 2.
            VStack(spacing: 0) {
                // Header is drawn UNCONDITIONALLY in every mode — including the VOD start
                // sequence (opening MP4 / loader): only the VOD side rail + floating bag are
                // suppressed there, the header stays (rb-ios-vod-intro-keep-header).
                PlayerHeaderBarView(
                    theme: theme,
                    title: model.title,
                    hostName: model.hostName,
                    shopLogo: model.shopLogo,
                    viewerCount: model.viewerCount,
                    isSubscribed: model.isSubscribed,
                    // live-chrome 家族（真直播 + 回放）皆餵 isLive: true → header 畫 viewer-count
                    // （回放套 LIVE 版型，rb-ios-replay-live-chrome）。
                    isLive: usesLiveChrome,
                    // Replay hides the LIVE pill but keeps the viewer count (design
                    // `hideLivePill = isReplay`). 兩種回放皆隱 LIVE 膠囊：behind-edge replay
                    // （`model.isReplay`，鏡像 playbackProgress.isReplay）與 finished-live replay
                    // （`model.isFinishedLiveReplay`，已結束直播）——後者非正在直播，顯紅 LIVE 會誤導。
                    isReplay: model.isReplay || model.isFinishedLiveReplay,
                    // Real shop logo only over a live video surface (placeholder suppressed) —
                    // reuse the same runtime image gate the cover/upcoming surfaces use; the
                    // snapshot/demo path (`paintsBackgroundPlaceholder == true`) stays monogram.
                    live: !paintsBackgroundPlaceholder,
                    // Host-config viewer-count gate (rb-ios-hide-viewer-count-config): default
                    // true; `false` (host) hides the viewer count even while live / replay.
                    showViewerCount: model.showViewerCount,
                    // Backend viewer-count gate (rb-ios-viewer-count-show-pv-num): mirrors
                    // `channel.show_pv_num == 1` via the view-model (same source as `viewerCount`).
                    // The badge shows ⟺ isLive && viewerCountVisible && showViewerCount — so replay
                    // (LIVE chrome) honours the original live-time show_pv_num setting.
                    viewerCountVisible: model.viewerCountVisible,
                    // Backend / merchant title-marquee capability gate (rb-ios-video-title-scroll):
                    // mirrors `extensions.video_title_scroll` via `LivebuyPlayerConfig.titleScroll`.
                    // `false` keeps the title (single line + ellipsis, same height) but stops it
                    // scrolling; the overflow MEASUREMENT itself is untouched.
                    titleScroll: model.titleScroll,
                    // Cold-start loading gate (rb-live-entry-viewer-count-loading-gate):
                    // mirrors `model.startPhase`. While `.loading` (the `/sdk/video` fetch
                    // has not yet resolved) the viewer-count badge is suppressed so a
                    // not-yet-real `viewerCount` (type default `0`) is never drawn as if it
                    // were a real count.
                    startPhase: model.startPhase,
                    // 乾淨模式隱藏「top bar logo」+「host badge」（design 兩個獨立元件，iOS 合併
                    // 成同一顆 hostPill）——保留頂欄唯一的 minimize(PIP) 鈕不受影響（rb-ios-gesture-
                    // clean-mode-rewrite ADDED Requirement，見 `PlayerHeaderBarView.cleanMode`）。
                    cleanMode: cleanMode,
                    onMinimize: { onMinimize?() },
                    // 訂閱徽章 → 容器注入的 gate（未登入 → AuthGate(.subscribe)）；未注入 fallback
                    // `model.toggleSubscribe()`（rb-ios-subscribe-login-gate）。與 info pill 共用。
                    onSubscribe: { performSubscribe() },
                    // Host badge tap → open the VideoInfoPanel (design LBPHostBadge →
                    // video_info; presentation-only, replaces the removed VOD rail
                    // `more` pill). Same presentation toggle the `more` pill used.
                    onTapHostBadge: { withAnimation { infoPanelPresented.toggle() } })

                Spacer(minLength: 0)

                // Side rail is VOD-ONLY chrome (design screens.jsx gates `LBPSideRail`
                // on `!isLive`; upcoming wears the slim LIVE bar instead). In LIVE /
                // upcoming the bottom bar (below) replaces it; the rail anchors HIGHER
                // (bottom ≈80) so the separate floating bag button (below) can sit lower
                // next to the mini-cart strip (design `LBPSideRail` bottom:80 vs
                // `LBPBagButton` bottom:16). Suppressed only during the VOD OPENING sequence
                // (full-screen loader `.loading` / intro MP4 `.splash`) — from `.buffering`
                // onward the rail shows (rb-ios-vod-rail-show-on-buffering). Additionally hidden
                // while actively dragging the playback-progress bar
                // (rb-ios-restore-vod-playback-progress-bar) — reappears (lifted, see padding
                // below) once the finger lifts. Side rail 在乾淨模式隱藏（rb-ios-gesture-clean-
                // mode-rewrite ADDED Requirement）。
                if showsVodMainChrome && !isScrubbing && !cleanMode {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        OperationRailView(
                            theme: theme,
                            items: model.railItems,
                            bagCount: model.bagCount,
                            heartBurstTick: model.heartBurstTick,
                            muted: model.muted,
                            onTapItem: { kind in
                                // The rail surfaces a tap intent; for the info kinds
                                // the shell can forward presentation-only navigation.
                                // Real actions (like / share / chat …) go through the
                                // host-wired core `simulate*` — NOT owned here (D-4).
                                handleRailTap(kind)
                            })
                            .padding(.trailing, 12)
                            .padding(.bottom, 80 + scrubChromeLiftIfExpanded)
                    }
                }
            }

            // Floating shopping-bag button (design `LBPBagButton`, VOD-only; upcoming's
            // bag lives in the slim LIVE bar instead) — composed as a SEPARATE sibling at
            // a LOWER anchor than the rail (bottom ≈16, trailing 12), next to the mini-cart
            // strip region. Tapping it reuses the existing goods path (`performGoodsTap` +
            // host `onOpenProductList`), behavior unchanged — only the trigger surface.
            // Suppressed only during the VOD OPENING sequence (full-screen loader
            // `.loading` / intro MP4 `.splash`); shows from `.buffering` onward, in lockstep
            // with the side rail (rb-ios-vod-rail-show-on-buffering). Additionally hidden while
            // actively dragging the playback-progress bar (rb-ios-restore-vod-playback-progress-bar).
            // Hidden in clean mode (rb-ios-gesture-clean-mode-rewrite ADDED Requirement).
            if showsVodMainChrome && !isScrubbing && !cleanMode {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        FloatingBagButtonView(
                            theme: theme,
                            bagCount: model.bagCount,
                            onTap: {
                                model.performGoodsTap()   // telemetry-only panel-toggle
                                onOpenProductList?()        // host opens the product list
                            })
                            .padding(.trailing, 12)
                            .padding(.bottom, 16 + scrubChromeLiftIfExpanded)
                    }
                }
            }

            // LIVE bottom bar — surfaces the design's `LBLiveBottomBar` at the bottom in
            // LIVE mode AND upcoming mode (VOD uses the side rail above instead). awaitingLive
            // passes `isUpcoming: true` → the SLIM variant (bag + share + like; no 留言 /
            // nickname / CC); the upcoming INTRO MP4 (`introPlaying`) passes `bagOnly: true`
            // → the bag-only minimal variant (just the bag). Pinned bottom, over the live
            // overlay chrome and below the info-panel modal. Nickname / share / like / CC
            // route through the model's existing turnkey forwarders (same host-wired path the
            // rail uses); 留言 raises the host `onComment` intent.
            //
            // Hidden while the on-demand chat composer is presented (`composerPresented`):
            // the composer replaces the 留言 entry and sits in the same bottom region, so the
            // bottom bar (+ its heart-burst sibling) is suppressed to avoid overlap
            // (rb-ios-chat-composer-opaque-hide-bottom-bar).
            // 拖曳播放進度條期間（isScrubbing）隱藏 LIVE 底部 bar（+ 愛心 burst），讓出畫面給
            // transport bar（design `screens.jsx` `LBLiveBottomBar` 的 `!(isReplay && scrubbing)`
            // gate）；放開手指到 2.8 秒收回這段期間（scrubBarExpanded && !isScrubbing）重新出現並
            // 上移，讓出底部 transport bar 空間。`isScrubbing` 只會在 `showsPlaybackProgressBar`
            // 為真時被觸發，故對 upcoming / introPlaying（永不與進度條共存）不受影響。
            //
            // 乾淨模式（rb-ios-gesture-clean-mode-rewrite ADDED Requirement）隱藏 LIVE 底部
            // bar —— 但範圍只限「因 usesLiveChrome 而顯示」的情況（真直播 / 已結束直播回放）；
            // upcoming / introPlaying 那段 slim bar 不在本次乾淨模式規範範圍內，`&& !cleanMode`
            // 只 AND 進 `usesLiveChrome` 那一支，不影響 `model.isUpcoming` / `model.introPlaying`
            // 那兩支。
            if ((usesLiveChrome && !cleanMode) || model.isUpcoming || model.introPlaying) && !composerPresented && !isScrubbing {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LiveBottomBarView(
                        theme: theme,
                        bagCount: model.bagCount,
                        isReplay: model.isReplay,
                        isUpcoming: model.isUpcoming || model.introPlaying,
                        // 直播預告的開場影片 (introPlaying) → bag-only minimal bar (just the bag).
                        // awaitingLive keeps the slim three-button bar. bagOnly takes precedence.
                        bagOnly: model.introPlaying,
                        // 回放（已結束直播）→ 留言改 disabled「聊天室已關閉」、暱稱隱藏（後端 commentsub
                        // 對 liveStatus==3 回 404；rb-ios-replay-chat-closed-bottom-bar）。behind-edge
                        // isReplay（仍直播）不受影響——chatClosed 只由 isFinishedLiveReplay 驅動。
                        chatClosed: model.isFinishedLiveReplay,
                        onBag: {
                            model.performGoodsTap()   // telemetry-only panel-toggle event
                            onOpenProductList?()       // host opens the product-list overlay
                        },
                        onComment: { onComment?() },
                        // Container wires `onNickname` to a LOCAL `GuestNameEditModalView`
                        // presentation; absent (non-container / snapshot) → fall back to the
                        // existing `model.requestGuestNameEdit()` forwarder (gated core path).
                        onNickname: { if let onNickname = onNickname { onNickname() } else { model.requestGuestNameEdit() } },
                        // dropin-player-default-share-sheet 的 fallback（presentChannelShare）
                        // 由容器經 `onShare` 注入（rb-ios-live-share-default-sheet）；非容器 /
                        // snapshot（onShare == nil）維持既有 headless `model.performShare()`。
                        onShare: { if let onShare = onShare { onShare() } else { model.performShare() } },
                        // Real like via the existing turnkey forwarder + an immediate local heart
                        // burst (rb-ios-live-bottom-heart-burst — design `onLike → spawnHeart`).
                        onLike: { model.performLike(); liveHeartTick &+= 1 })
                        // onToggleCC intentionally not wired: the LIVE bottom bar no longer has a CC
                        // toggle (the replay variant is removed — prerecorded-live-bottom-bar-comment).
                        // rb-ios-live-bottom-bar-16pt-align: no static offset here — LiveBottomBarView
                        // itself now owns the full 16pt bottom inset internally (barBottomPadding), so
                        // its background sits flush against the true bottom edge (design `bottom: 0`).
                        // Only the dynamic post-scrub-release lift remains.
                        .padding(.bottom, scrubChromeLiftIfExpanded)
                }

                // LIVE bottom-bar heart burst — the shared `HeartBurstView` anchored ABOVE the
                // like button (bottom-trailing), driven by the local `liveHeartTick`. Bag-only
                // (introPlaying) draws no like → no burst. Transient + non-interactive →
                // snapshot-neutral at rest. (rb-ios-live-bottom-heart-burst)
                // 心動特效在乾淨模式隱藏（rb-ios-gesture-clean-mode-rewrite ADDED Requirement）——
                // 同上，範圍只限 usesLiveChrome 那一支，不影響 upcoming。
                if ((usesLiveChrome && !cleanMode) || model.isUpcoming) && !model.introPlaying {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HeartBurstView(tick: liveHeartTick, color: theme.accent)
                        }
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 64 + scrubChromeLiftIfExpanded)
                    .allowsHitTesting(false)
                }
            }

            // Center gesture-feedback overlays. ZStack centers them.
            //
            // Paused overlay (rb-ios-gesture-clean-mode-rewrite, supersedes the retired
            // `GesturePauseIconView`/`isHolding` pairing): driven by the REAL `model.isPlaying`
            // (not a gesture transient) — shows for as long as the engine is actually paused,
            // however that pause was triggered (a VOD/replay tap via `resolveTapAction`, or an
            // SDK-internal lifecycle `pause()`). Gated on `isMainPlaybackPhase` (mirrors
            // `showsPlaybackProgressBar`'s `isMain`) so the cold-start loader / intro MP4 window
            // — where `model.isPlaying` defaults `false` before any real playback state exists —
            // never shows it. UNLIKE the retired static icon, this overlay IS interactive (two
            // buttons), so it does NOT carry `.allowsHitTesting(false)`.
            if isMainPlaybackPhase && !model.isPlaying {
                PlaybackPausedOverlayView(
                    theme: theme,
                    muted: model.muted,
                    onToggleMute: onToggleMute,
                    onResume: { model.togglePlayPause() })
            }
            // Mute toast: 0.7s tap-to-mute feedback (reads model.muted = the post-toggle state).
            // Non-interactive (allowsHitTesting false) so it never blocks the gesture layer /
            // chrome below.
            if muteToastVisible {
                GestureMuteToastView(theme: theme, muted: model.muted)
                    .allowsHitTesting(false)
            }

            // VOD / replay playback-progress transport bar (rb-ios-restore-vod-playback-
            // progress-bar, SUPERSEDES rb-ios-retire-vod-progress-bar 2026-06-10). Composed as
            // an independent top-level ZStack sibling — NOT nested in either the VOD or
            // `usesLiveChrome` branch above — because it must render over BOTH (pure VOD via
            // the VOD branch; a finished-live replay or a live stream scrubbed behind the live
            // edge via the `usesLiveChrome` branch). Pinned to the very bottom edge. All
            // interactions forward to `PlayerShellModel`'s EXISTING `togglePlayPause()` /
            // `seek(to:)` forwarders — no new core / view-model API.
            if showsPlaybackProgressBar {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PlaybackProgressBarView(
                        theme: theme,
                        position: model.position,
                        duration: model.duration,
                        isPlaying: model.isPlaying,
                        isScrubbing: isScrubbing,
                        // 乾淨模式：進度條從細線態直接展開為完整可互動 transport 列（design
                        // `screens.jsx` 既有的 `(scrubVisible || cleanMode)` 開關模式，rb-ios-
                        // gesture-clean-mode-rewrite ADDED Requirement）。
                        isExpanded: scrubBarExpanded || cleanMode,
                        onTogglePlayPause: { model.togglePlayPause() },
                        onScrubStarted: { handleScrubStarted() },
                        onScrub: { ratio in handleScrub(ratio) },
                        onScrubEnded: { handleScrubEnded() })
                }
            }

            // 會員等級限定升級遮罩（restriction-mask ②）。`is_restriction` 為**軟性顯示閘門**：
            // core 不擋播放，reference-ui 在播放畫面上疊遮罩 + 升級提示。預設隱藏
            // （`model.isRestricted == false`）→ snapshot baseline byte-identical。最終視覺 /
            // 退出 affordance DECISION-PENDING 待設計稿。
            if model.isRestricted {
                RestrictionMaskView(theme: theme)
            }
        }
        // Info panel (family-1 surface 3) — presented via the shared SheetKit bottom-sheet
        // presenter (dim scrim + grab handle + drag-to-dismiss). FOUR dismiss paths now
        // converge on `infoPanelPresented = false`: drag the handle past threshold, tap the
        // scrim, re-tap the host badge, or tap the header close icon (all animated; the close
        // icon added by rb-ios-sheet-header-close-unify). Replaces the prior hand-rolled
        // `VStack { Spacer(); if … { … .transition } }` that had no scrim / no dismiss.
        .lbBottomSheet(theme: theme, isPresented: $infoPanelPresented) {
            VideoInfoPanelView(
                theme: theme,
                info: model.infoTab,
                activeTab: model.activeTab,
                canOpenNotice: model.canOpenNotice,
                systemNotice: model.systemNotice,
                notice: model.notice,
                // 商家列的真實 logo 圖片閘門 — 與上方 header avatar 呼叫點（`live:` 同一行運算式）
                // 共用**同一來源**，而非各自推導：兩個 surface 畫的是同一顆 `shopLogo`，gate 一旦
                // 分岔就會出現「header 已顯真 logo、面板仍是字母漸層」這種跨面不一致。
                // snapshot / demo 路徑（`paintsBackgroundPlaceholder == true`）維持漸層 chip、不觸網。
                live: !paintsBackgroundPlaceholder,
                onSelectTab: { tab in model.selectInfoTab(tab) },
                // 與商家一對一對話 → present the「聯絡商家」confirm modal FIRST (design
                // `contact_merchant`), same intent as the side-rail serviceLink tap; only its
                // 「確定」proceeds to the existing service-link exit. (前往商城首頁 / storefront
                // has no core exit yet; it renders for design fidelity and stays inert.)
                onContactMerchant: { withAnimation { contactMerchantPresented = true } },
                // header 右上角關閉 icon → 關面板（第四個合法關閉入口，rb-ios-sheet-header-close-unify）。
                onClose: { withAnimation { infoPanelPresented = false } },
                // 訂閱 pill → 與 header 頭像徽章共用同一注入 gate（未登入 → 本地 AuthGate(.subscribe)、
                // 已登入 → toggleSubscribe）；未注入 fallback `model.toggleSubscribe()`
                // （rb-ios-subscribe-login-gate，取代原本一律直接 toggleSubscribe 的寫法）。
                onSubscribe: { performSubscribe() })
        }
        // 「聯絡商家」confirm modal — composed ABOVE the info-panel sheet so it overlays it.
        .overlay(contactMerchantOverlay)
        // Report info-panel open/closed to the container so it can hide the higher-layer
        // chat feed while the panel is up (rb-ios-info-panel-not-covered-by-chat). Read-only
        // report — the panel state / dismiss paths are unchanged.
        .onChange(of: infoPanelPresented) { presented in
            onInfoPanelPresentedChange?(presented)
        }
        // Report LIVE/VOD mode (initial + every change) so the container can hide the LIVE-only
        // chat feed in VOD (rb-ios-hide-chat-feed-in-vod). `.onAppear` supplies the initial value
        // (`.onChange` does not fire for it); `.onChange` tracks switches between videos.
        .onAppear {
            // 回報 live-chrome 家族（真直播 + 回放）而非僅 isLive，使回放也顯示聊天 feed
            // （rb-ios-replay-live-chrome）。
            onIsLiveChange?(usesLiveChrome)
            // 初值報告 announce 顯示與否（`.onChange` 不會為初值觸發），讓容器一進場就給對的避讓。
            onHasAnnounceChange?(!model.announceText.isEmpty)
            // 初值報告 cleanMode（`.onChange` 不會為初值觸發），讓容器一進場（含測試以
            // `cleanModeForTesting` 預先 seed 的情境）就拿到正確初值（rb-ios-clean-mode-hide-
            // chat-feed）。
            onCleanModeChange?(cleanMode)
        }
        .onChange(of: model.isLive) { _ in
            onIsLiveChange?(usesLiveChrome)
        }
        // 回報 cleanMode 每次翻轉（長按觸發）給容器，讓 family-2 聊天 feed 跟著隱藏/恢復
        // （rb-ios-clean-mode-hide-chat-feed）。
        .onChange(of: cleanMode) { newValue in
            onCleanModeChange?(newValue)
        }
        // 回放旗標切換亦回報 live-chrome 家族（換片 live→回放 / 回放→VOD 時聊天 feed 跟著開關）。
        .onChange(of: model.isFinishedLiveReplay) { _ in
            onIsLiveChange?(usesLiveChrome)
        }
        // Report whether the LBLiveAnnounce banner is showing (announceText 非空) so the container
        // gives the chat feed extra bottom clearance only when a 公告 is present
        // (rb-ios-live-announce-chat-clearance, 問題 4). announceText 只在後台公告變更時才變，不頻繁。
        .onChange(of: model.announceText) { text in
            onHasAnnounceChange?(!text.isEmpty)
        }
        // App 進背景（含觸發系統自動 PiP）時，若正在拖曳進度條，`DragGesture` 沒有「被系統中斷」
        // 的回呼可掛（`.onEnded` 永遠不會收到 `touchesCancelled`），視同放開手指走既有
        // `handleScrubEnded()` 路徑，避免從背景/PiP 返回後拖曳讀數卡在展開態
        // (ios-scrub-reset-on-background-reference-ui)。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            handleDidEnterBackground()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.playerShell)
    }

    /// 訂閱 tap 的統一分派（header 頭像徽章 + VideoInfoPanel 訂閱 pill 共用一份 → 決策一致）：容器
    /// 注入的 `onSubscribe` gate（未登入 → 本地 `AuthGateModalView(.subscribe)`、已登入 →
    /// toggleSubscribe）優先；未注入（demo / snapshot / 非容器）→ fallback `model.toggleSubscribe()`
    /// 以保既有路徑與 snapshot baseline 不變（rb-ios-subscribe-login-gate）。
    private func performSubscribe() {
        if let onSubscribe = onSubscribe { onSubscribe() } else { model.toggleSubscribe() }
    }

    /// Forward a side-rail tap to its turnkey destination (TK-3). Every kind is now
    /// handled (no swallow): the action kinds forward to the bound template's perform-
    /// methods via `model` (→ core public exits → not-intercepted design default
    /// flow); `.goods` / `.chat` raise host open-intents (the overlay composition is
    /// host-owned); `.more` toggles the local info-panel presentation. The model
    /// forwarders are no-ops on demo / snapshot instances (no bound template).
    private func handleRailTap(_ kind: LBSideRailKind) {
        // The aligned VOD rail (design `LBPSideRail`) surfaces ONLY subtitle / share /
        // serviceLink. The other kinds are unreachable from the rail: goods → the
        // separate floating bag button; info → the host-badge tap; like / nickname /
        // chat are LIVE bottom-bar / not-in-VOD-rail. Switch stays total for
        // compile-time exhaustiveness.
        switch kind {
        case .subtitle:
            model.toggleSubtitle()
        case .share:
            // 與 LIVE 底部 bar 分享同一走線：容器注入的 `onShare`（含 presentChannelShare
            // fallback）→ unwired host 也能分享；非容器 / snapshot（onShare == nil）維持既有
            // headless `model.performShare()`（rb-ios-vod-rail-share-default-sheet）。
            if let onShare = onShare { onShare() } else { model.performShare() }
        case .serviceLink:
            // Design `contact_merchant`: confirm BEFORE opening the service link. Present
            // the confirm modal; only its「確定」proceeds to `model.openServiceLink()`.
            withAnimation { contactMerchantPresented = true }
        case .goods, .chat, .like, .guestNameEdit, .more:
            break   // not reachable from the aligned rail
        }
    }

    /// The「聯絡商家」confirm modal overlay (design `contact_merchant` → `LBPAlertModal`),
    /// composed ABOVE the info-panel sheet. Presented when the rail serviceLink or the
    /// info-panel「與商家一對一對話」intent fires;「確定」proceeds to the existing
    /// `model.openServiceLink()` exit, 「取消」/ scrim just dismisses.
    @ViewBuilder
    private var contactMerchantOverlay: some View {
        if contactMerchantPresented {
            ContactMerchantModalView(
                theme: theme,
                onConfirm: {
                    withAnimation { contactMerchantPresented = false }
                    model.openServiceLink()
                },
                onDismiss: { withAnimation { contactMerchantPresented = false } })
                .transition(.opacity)
        }
    }
}

// MARK: - iOS-14-safe full-bleed helper (D-7)

private extension View {
    /// `ignoresSafeArea()` is iOS-14+; `edgesIgnoringSafeArea(.all)` is the
    /// iOS-13/14-safe equivalent. Keep the call site clean and the guard local.
    @ViewBuilder
    func ignoresSafeAreaCompat() -> some View {
        if #available(iOS 14.0, *) {
            self.ignoresSafeArea()
        } else {
            self.edgesIgnoringSafeArea(.all)
        }
    }
}

// MARK: - Restriction mask (restriction-mask ②)

/// 會員等級限定升級遮罩：全幅暗罩 + 鎖 glyph + 升級提示。`is_restriction` 為**軟性顯示閘門**
/// （core 不擋播放、後端仍回完整內容），此遮罩疊在播放畫面上擋住受限內容。只在
/// `PlayerShellView` 偵測 `model.isRestricted == true` 時建出，故未受限時不出像素
/// （snapshot baseline byte-identical）。最終視覺 / 退出 affordance DECISION-PENDING 待設計稿。
private struct RestrictionMaskView: View {
    let theme: ReferenceUITheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
            VStack(spacing: 10) {
                LockGlyph(size: 30, color: .white)
                Text("此內容限定會員等級觀看")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("提升會員等級後即可觀看")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(24)
            .multilineTextAlignment(.center)
        }
        // 擋住受限內容（軟閘門：阻擋與下層播放內容互動）。
        .contentShape(Rectangle())
    }
}
