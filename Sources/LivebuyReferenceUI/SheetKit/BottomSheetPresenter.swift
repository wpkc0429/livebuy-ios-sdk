import SwiftUI
import UIKit

// MARK: - Half-screen height cap gate (rb-ios-sheet-half-height)
//
// Production caps every bottom sheet at HALF the screen height (content-sized up to the cap,
// then scrolls within it). The reference-ui snapshot path renders THROUGH this presenter via
// `ImageRenderer`, which renders `ScrollView` content BLANK and never re-renders on the
// `GeometryReader` height measurement. So the snapshot tests set `lbSheetHeightUncapped = true`
// to render the card content-sized (no ScrollView, no cap) — byte-identical to the pre-cap
// baselines. Production leaves it `false` → the cap + scroll applies. (Internal; the snapshot
// tests reach it via `@testable import`.)
private struct SheetHeightUncappedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var lbSheetHeightUncapped: Bool {
        get { self[SheetHeightUncappedKey.self] }
        set { self[SheetHeightUncappedKey.self] = newValue }
    }
}

// MARK: - Drag-resize height override (rb-ios-sheetkit-resize-dismiss-unify, originally
// rb-ios-product-sheet-resize-fav-inline)
//
// `BottomSheetChrome` (the presenter) measures the drag and computes a live height FRACTION;
// `LBSheetScaffold` (the leaf) is what actually computes `cap` / drives the body frame. This
// environment key is the one channel between them: `BottomSheetChrome` sets it (non-nil) once
// the user has dragged the handle at least once during the CURRENT presentation; `nil` (the
// default) means "no override — use the leaf's own `capFraction` / `fillToCap`". EVERY
// `.lbBottomSheet(...)` call site (both the `isPresented:` and `item:` overloads) can set this
// to non-nil — the resize/dismiss gesture is now universal across all 5 real bottom sheets, not
// an opt-in limited to the product-sheet stack (see `BottomSheetChrome.dragGesture` below).
private struct SheetHeightFractionOverrideKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var lbSheetHeightFractionOverride: CGFloat? {
        get { self[SheetHeightFractionOverrideKey.self] }
        set { self[SheetHeightFractionOverrideKey.self] = newValue }
    }
}

// MARK: - Drag-in-progress signal (rb-ios-sheetkit-resize-dismiss-unify)
//
// `LBSheetScaffold` reads this to FREEZE its header/footer/body `GeometryReader` measurements
// while a resize/dismiss drag gesture is actively tracking touch moves (see the anti-jitter note
// on `LBSheetScaffold`'s `onPreferenceChange` handlers below). `BottomSheetChrome` sets it
// `true` for the span of `dragGesture` (`onChanged` ... `onEnded`) and `false` otherwise.
private struct SheetIsDraggingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var lbSheetIsDragging: Bool {
        get { self[SheetIsDraggingKey.self] }
        set { self[SheetIsDraggingKey.self] = newValue }
    }
}

/// Reports the intrinsic height of a sheet region (header / body / footer) so `LBSheetScaffold`
/// can size the scrollable body UP TO the half-screen cap minus the pinned chrome. Consulted only
/// on the production (capped) path.
private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct SheetHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct SheetFooterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Background height reporter for one sheet region.
private func sheetHeightReader<K: PreferenceKey>(_ key: K.Type) -> some View where K.Value == CGFloat {
    GeometryReader { geo in Color.clear.preference(key: key, value: geo.size.height) }
}

/// Same as `sheetHeightReader(_:)`, but the underlying `GeometryReader` is only MOUNTED while
/// `active` is true — when `active == false` this is an `EmptyView`, not merely a reader whose
/// output is ignored. Mounting/unmounting a `GeometryReader` on every touch-move sample of an
/// active drag (rather than just discarding its measured result) is what removes the actual
/// per-frame layout-measurement COST, not only the resulting `@State` write — see
/// rb-ios-sheet-resize-drag-render-cost-jitter: freezing only the *result* of a `GeometryReader`
/// still leaves its measurement PASS running on every re-render, a real per-frame cost distinct
/// from the one-frame-behind feedback loop `rb-ios-sheetkit-resize-dismiss-unify` fixed.
@ViewBuilder
private func sheetHeightReader<K: PreferenceKey>(
    _ key: K.Type, active: Bool
) -> some View where K.Value == CGFloat {
    if active {
        sheetHeightReader(key)
    }
}

// MARK: - LBSheetScaffold — pinned header + scrollable body + pinned footer (rb-ios-sheet-pinned-header-footer)
//
// Every grab-handle bottom sheet leaf wraps its three regions in `LBSheetScaffold` so the HEADER
// (title / tabs / close) and FOOTER (CTA / toggle) stay PINNED while only the BODY scrolls — and
// the WHOLE sheet stays ≤ half the screen height.
//
//   • Production (`lbSheetHeightUncapped == false`, default): `VStack { header; ScrollView{body}; footer }`
//     where the body's scroll viewport = `min(bodyIntrinsic, ½screen − header − footer)` (measured
//     via background GeometryReaders). Short sheets stay content-sized; tall ones scroll the body
//     between the pinned header/footer, total ≤ ½ screen.
//   • Snapshot/ImageRenderer (`lbSheetHeightUncapped == true`, set by reference-ui snapshot tests):
//     `VStack { header; body; footer }` — content-sized, NO ScrollView (ImageRenderer renders
//     ScrollView blank). This is byte-identical to the leaf's prior flat `VStack`, so baselines
//     stay unchanged.
struct LBSheetScaffold<Header: View, BodyContent: View, Footer: View>: View {
    @Environment(\.lbSheetHeightUncapped) private var uncapped
    /// Live drag-resize override (rb-ios-sheetkit-resize-dismiss-unify), set by
    /// `BottomSheetChrome` once the user has dragged the handle during the current presentation
    /// (any of the 5 real bottom sheets). `nil` (the default — before the first drag this
    /// presentation) → this scaffold's own `fillToCap` / `capFraction` decide `cap`, unaffected.
    @Environment(\.lbSheetHeightFractionOverride) private var heightFractionOverride
    /// Whether a resize/dismiss drag gesture is CURRENTLY tracking touch moves
    /// (rb-ios-sheetkit-resize-dismiss-unify) — see the anti-jitter note on the
    /// `onPreferenceChange` handlers below.
    @Environment(\.lbSheetIsDragging) private var isDragging

    /// `true` → 固定高度填滿到 cap（content 頂部對齊、footer 釘底、不足處下方留白、超出則捲動），
    /// body-fill 行為對齊設計稿；cap 固定 0.4 螢幕（rb-ios-compact-sheet-cap-and-footer；原
    /// rb-ios-addtocart-sheet-height-align-restock 為設計 `min(drawerH, 70%)` 的 0.7，已由產品覆蓋）。
    /// `false`（預設）→ content-sized（既有行為），cap 改讀 `capFraction`。snapshot（`uncapped`）
    /// 路徑不受此旗標影響。宣告於三個 `@ViewBuilder` 閉包之前，使多重 trailing-closure call site 仍可用。
    var fillToCap: Bool = false
    /// The non-`fillToCap` cap fraction (screen-height multiplier) for THIS instance. Defaults to
    /// `0.5`, shared by every content-sized leaf — `VideoInfoPanelView` / `ProductListView` /
    /// `ProductDetailSheetView`'s `.detail` presentation all rely on this default (none pass
    /// `capFraction` explicitly). `rb-ios-product-sheet-resize-fav-inline` had `.detail` pass
    /// `0.9` explicitly as its STATIC cap; `rb-ios-sheetkit-resize-dismiss-unify` reverted that —
    /// `0.9` is now purely the shared drag-resize ceiling (`BottomSheetChrome.resizeCeilingFraction`),
    /// reachable by dragging the handle up, not any leaf's static default. Ignored when
    /// `fillToCap == true` (that branch always uses `0.4`).
    var capFraction: CGFloat = 0.5

    @ViewBuilder var header: () -> Header
    @ViewBuilder var bodyContent: () -> BodyContent
    @ViewBuilder var footer: () -> Footer

    @State private var headerH: CGFloat = 0
    @State private var footerH: CGFloat = 0
    @State private var bodyH: CGFloat = 0

    /// `fillToCap` sheet 固定 0.4 螢幕高（精簡購買 / 補貨 sheet 的產品指定高度，覆蓋設計
    /// `min(drawerH, 70%)`；rb-ios-compact-sheet-cap-and-footer）；一般 sheet 維持 `capFraction`
    /// （預設 0.5）。使用者拖曳出的 `heightFractionOverride`（非 nil 時）整段取代這兩者——現為
    /// 全部 5 個 bottom sheet 共用的行為（rb-ios-sheetkit-resize-dismiss-unify，取代原本僅
    /// `.lbBottomSheet(item:)` 三張 sheet 才有的 opt-in）。
    private var cap: CGFloat {
        let fraction = heightFractionOverride ?? (fillToCap ? 0.4 : capFraction)
        return UIScreen.main.bounds.height * fraction
    }
    /// `true` when the sheet should FILL to `cap` (content top-aligned, footer pinned, extra space
    /// blank / scrollable) rather than stay content-sized: either the leaf opted into `fillToCap`,
    /// or the user has live-resized this presentation (in which case the resized height should be
    /// visibly filled, same semantics as `fillToCap`).
    private var effectiveFillToCap: Bool { fillToCap || heightFractionOverride != nil }
    /// Body scroll viewport = cap 減去釘住的 header + footer（floored 使 chrome 過高時仍留可捲區），
    /// 維持整張 sheet ≤ cap。
    private var bodyMax: CGFloat { Self.bodyViewport(cap: cap, headerH: headerH, footerH: footerH) }

    /// Pure：body 捲動視窗高 = `max(120, cap - header - footer)`。抽出供單元測（fillToCap 同高保證）。
    static func bodyViewport(cap: CGFloat, headerH: CGFloat, footerH: CGFloat) -> CGFloat {
        max(120, cap - headerH - footerH)
    }

    /// Pure：`fillToCap` 時整張 sheet 總高 = `header + bodyViewport + footer`。當 `cap - header - footer ≥ 120`
    /// 時恆等於 `cap`（與 header/footer 高度無關）——這保證**不同 footer 的 AddToCart 與 NotifyRestock
    /// 在同一 cap 下固定同高**（rb-ios-addtocart-sheet-height-align-restock）。抽出供單元測。
    static func filledSheetHeight(cap: CGFloat, headerH: CGFloat, footerH: CGFloat) -> CGFloat {
        headerH + bodyViewport(cap: cap, headerH: headerH, footerH: footerH) + footerH
    }

    var body: some View {
        if uncapped {
            // Snapshot / ImageRenderer：維持 content-sized（無 ScrollView / 無 cap），baseline 確定性。
            // `fillToCap` 在此路徑無效（cap 行為本來就不進 snapshot，見檔頭 rb-ios-sheet-half-height）。
            VStack(spacing: 0) {
                header()
                bodyContent()
                footer()
            }
        } else {
            VStack(spacing: 0) {
                header().background(sheetHeightReader(SheetHeaderHeightKey.self, active: !isDragging))
                ScrollView {
                    bodyContent().background(sheetHeightReader(SheetContentHeightKey.self, active: !isDragging))
                }
                // `effectiveFillToCap`（`fillToCap` 或使用者已拖曳出高度覆寫）：固定填滿到 bodyMax
                // （content 頂部對齊、下方留白 / 超出捲動）→ sheet 固定 = cap。否則 content-sized（既有行為）。
                .frame(height: effectiveFillToCap ? bodyMax : (bodyH <= 0 ? bodyMax : min(bodyH, bodyMax)))
                footer().background(sheetHeightReader(SheetFooterHeightKey.self, active: !isDragging))
            }
            // Anti-jitter freeze (rb-ios-sheetkit-resize-dismiss-unify, hardened by
            // rb-ios-sheet-resize-drag-render-cost-jitter): while a drag gesture is actively
            // tracking touch moves (`isDragging == true`), these three `GeometryReader`s are
            // UNMOUNTED entirely (see the `active:` overload of `sheetHeightReader` above) — not
            // merely present-but-ignored. The original fix (guarding the `onPreferenceChange`
            // write below with `if !isDragging`) only stopped the *result* from reaching `@State`;
            // the `GeometryReader`s themselves kept re-running their layout-measurement pass on
            // every touch-move sample regardless, a real per-frame cost (3 readers here + one more
            // in `BottomSheetChrome.card` for the resize floor) that could miss a frame budget and
            // show up as a persistent stutter during the drag itself — most visible on slow drags,
            // where the same-size hitch is a larger fraction of the expected per-frame motion.
            // Unmounting removes that cost outright. `cap` / `bodyMax` recompute from a FROZEN
            // header/footer pair instead, driven purely by `heightFractionOverride` (no round trip
            // through this scaffold's own layout). Measurement resumes immediately once the
            // gesture ends (`isDragging` flips back to `false`, remounting the readers), so content
            // that changes BETWEEN gestures (e.g. the add-to-cart CTA spinner altering footer
            // height) is still picked up correctly. The `if !isDragging` guards below are kept as a
            // defensive no-op belt-and-braces — they should never fire while unmounted, since an
            // unmounted `GeometryReader` reports no preference at all.
            .onPreferenceChange(SheetHeaderHeightKey.self) { if !isDragging { headerH = $0 } }
            .onPreferenceChange(SheetFooterHeightKey.self) { if !isDragging { footerH = $0 } }
            .onPreferenceChange(SheetContentHeightKey.self) { if !isDragging { bodyH = $0 } }
        }
    }
}

// MARK: - SheetKit BottomSheetPresenter — the shared bottom-sheet chrome
//
// One iOS-14-safe presenter for EVERY grab-handle bottom sheet (`VideoInfoPanelView` /
// `ProductListView` here; `ProductDetailSheetView` / `NotifyRestockSheetView` via
// `sheetkit-migrate`). It owns the modal chrome so the leaf sheets carry only their content:
//
//   • full-bleed dim scrim (a transparent `Button` over `Color.black.opacity(0.55)` — the
//     iOS-14-safe recipe proven by `GuestNameEditModalView`; NOT an `onTapGesture` on a
//     `Color`, which renders unreliably headless). Tapping the scrim dismisses, and because
//     it sits ABOVE the host content it also blocks the video gesture layer below.
//   • bottom-anchored card with the shared `SheetGrabHandle` + `theme.background` +
//     `TopRoundedRectangle(20)` + the house shadow.
//   • UNIFIED drag-to-resize + drag-to-dismiss on the HANDLE strip
//     (rb-ios-sheetkit-resize-dismiss-unify, replacing the prior two independent states — an
//     up-drag-only resize opt-in + a down-drag-only dismiss): the sheet content's height FLOOR
//     is THIS presentation's own default/resting height (`floorFraction`, latched once from the
//     first real measurement of `sheetContent()` alone — see `CardHeightKey` below), the CEILING is a shared
//     `resizeCeilingFraction` (90%) across all 5 real bottom sheets. Dragging UP grows the
//     height toward the ceiling; dragging DOWN shrinks it back toward the floor — only once the
//     floor is reached does FURTHER downward drag convert into the `dragOffset` dismiss-peek
//     (100pt threshold, unchanged from before). See `dragState(...)` for the pure state-machine
//     math and its equivalence proof for sheets the user never drags taller than their floor.
//   • scrim `.opacity` + card `.move(edge:.bottom)` enter/exit transitions.
//   • Anti-jitter freeze while a resize/dismiss drag is tracking touch moves
//     (rb-ios-sheetkit-resize-dismiss-unify, hardened by
//     rb-ios-sheet-resize-drag-render-cost-jitter): `LBSheetScaffold` UNMOUNTS its
//     header/footer/body `GeometryReader`s entirely for the gesture's duration
//     (`lbSheetIsDragging` environment key) — not merely discards their result — breaking BOTH
//     the one-frame-behind feedback loop that produced the original visible jitter (prior
//     resize-only state changing `heightFraction` on every touch move) AND the ongoing per-frame
//     layout-measurement COST of four live `GeometryReader`s during any drag, which could miss a
//     frame budget and show up as a persistent stutter through the drag itself (most visible on
//     slow drags). `BottomSheetChrome.card`'s own `CardHeightKey` reader is similarly unmounted
//     once `floorFraction` latches, since nothing consumes it past that point anyway.
//
// Presentation state stays with the CONTAINER (`isPresented` / `item` bindings); the presenter
// only renders chrome + forwards `onDismiss`. `DragGesture` / `.offset` / `withAnimation` /
// `Button` / `.transition` are all iOS-13+ — no `if #available` needed.

public extension View {
    /// Present `content` as a shared bottom sheet while `isPresented` is true. Dismiss paths
    /// (drag the handle past threshold / tap the scrim) set `isPresented = false` and call
    /// `onDismiss`.
    func lbBottomSheet<SheetContent: View>(
        theme: ReferenceUITheme,
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(BottomSheetPresentedModifier(
            theme: theme, isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }

    /// `item:` overload (mirrors `.sheet(item:)`) so `sheetkit-migrate` can replace the one
    /// real `.sheet(item:)` (product detail / restock) with the shared chrome.
    ///
    /// Drag-to-resize + drag-to-dismiss (rb-ios-sheetkit-resize-dismiss-unify) apply
    /// UNCONDITIONALLY to every presentation through this overload — there is no longer an
    /// opt-in flag (the prior `resizable: Bool` parameter is removed); see
    /// `BottomSheetChrome.dragGesture` for the unified gesture.
    func lbBottomSheet<Item: Identifiable, SheetContent: View>(
        theme: ReferenceUITheme,
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(BottomSheetItemModifier(
            theme: theme, item: item, onDismiss: onDismiss, sheetContent: content))
    }
}

// MARK: - Presenter-owned slide animation
//
// The shared sheet slide curve (design `lbp-sheet-in`, sdk-components.jsx:
// `cubic-bezier(0.32, 0.72, 0.18, 1)` / 0.32s). `timingCurve` is iOS-13+.
//
// The presenter OWNS this animation so EVERY bottom sheet slides up on present and
// down on dismiss REGARDLESS of whether the caller wrapped the present/dismiss toggle
// in `withAnimation` (the prior fragility: VideoInfoPanel / ProductList wrapped it and
// slid, but ProductDetail / NotifyRestock — presented via `syncPresentation`'s plain
// `onChange` — popped instead of slid). Each modifier mirrors its binding into an
// internal `@State` flipped inside `withAnimation(sheetSlide)`, so the chrome's
// `.transition(.move(.bottom))` always plays. The `@State` is seeded from the binding's
// value in `init` (NOT `onAppear`) so the `ImageRenderer` snapshot path — which runs no
// `onAppear` / animation — still renders the chrome at `.constant(true)` (baselines
// stay byte-identical).
/// Duration (seconds) shared by `sheetSlide` and (rb-ios-sheet-drag-dismiss-jitter) the
/// `DispatchQueue.main.asyncAfter` delay that defers `onDismiss()` until the drag-to-dismiss
/// slide-out finishes — a single named source so the two can't drift out of sync.
private let sheetSlideDuration: TimeInterval = 0.32
private let sheetSlide = Animation.timingCurve(0.32, 0.72, 0.18, 1, duration: sheetSlideDuration)

// MARK: - Modifiers

struct BottomSheetPresentedModifier<SheetContent: View>: ViewModifier {
    let theme: ReferenceUITheme
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: () -> SheetContent

    /// Presenter-owned presence mirror. Seeded from the binding in `init` (so the
    /// ImageRenderer static path renders the chrome at `.constant(true)`), then flipped
    /// inside `withAnimation(sheetSlide)` on every binding change so present/dismiss slide.
    @State private var presented: Bool

    init(theme: ReferenceUITheme,
         isPresented: Binding<Bool>,
         onDismiss: (() -> Void)?,
         @ViewBuilder sheetContent: @escaping () -> SheetContent) {
        self.theme = theme
        self._isPresented = isPresented
        self.onDismiss = onDismiss
        self.sheetContent = sheetContent
        self._presented = State(initialValue: isPresented.wrappedValue)
    }

    func body(content: Content) -> some View {
        ZStack {
            content
            if presented {
                BottomSheetChrome(theme: theme, onDismiss: dismiss) { sheetContent() }
            }
        }
        // Mirror the binding into `presented` inside the slide animation so present
        // (slide up) and dismiss (slide down) animate even when the caller flips
        // `isPresented` without its own `withAnimation`.
        .onChange(of: isPresented) { newValue in
            withAnimation(sheetSlide) { presented = newValue }
        }
    }

    private func dismiss() {
        // scrim tap / drag past threshold → drive the binding false (the onChange mirror
        // plays the slide-down) + forward onDismiss. No inline withAnimation needed.
        isPresented = false
        onDismiss?()
    }
}

struct BottomSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    let theme: ReferenceUITheme
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: (Item) -> SheetContent

    /// Presenter-owned presence mirror (seeded from the binding in `init`).
    @State private var presented: Bool
    /// The item whose content is drawn. Captured on present / switch; RETAINED during the
    /// slide-down (when the binding is already nil) so the exit transition has content.
    /// Dynamic fields (variant / qty / cartCount) still read live from the model in the
    /// `sheetContent` closure on every re-render — `displayItem` only carries the static
    /// product fields + the exit content.
    @State private var displayItem: Item?

    init(theme: ReferenceUITheme,
         item: Binding<Item?>,
         onDismiss: (() -> Void)?,
         @ViewBuilder sheetContent: @escaping (Item) -> SheetContent) {
        self.theme = theme
        self._item = item
        self.onDismiss = onDismiss
        self.sheetContent = sheetContent
        self._presented = State(initialValue: item.wrappedValue != nil)
        self._displayItem = State(initialValue: item.wrappedValue)
    }

    func body(content: Content) -> some View {
        ZStack {
            content
            if presented, let shown = displayItem {
                BottomSheetChrome(theme: theme, onDismiss: dismiss) { sheetContent(shown) }
            }
        }
        .onChange(of: item?.id) { _ in
            if let current = item { displayItem = current }   // entering / switching → capture content
            withAnimation(sheetSlide) { presented = (item != nil) }
        }
    }

    private func dismiss() {
        item = nil
        onDismiss?()
    }
}

// MARK: - Drag-release decision (rb-ios-sheet-drag-dismiss-jitter)
//
// Pure decision extracted from `BottomSheetChrome.dragGesture`'s `onEnded` so the threshold
// logic is unit-testable without SwiftUI gesture simulation (this target has no ViewInspector /
// UI-automation infra — see `BottomSheetDragDismissOutcomeTests.swift`). Release past the
// threshold used to call `onDismiss()` immediately while `dragOffset` stayed at its release-time
// value un-animated; the container's own `.transition(.move(edge:.bottom))` would then animate
// the slide-out from scratch, unaware of the already-applied drag offset — two independent,
// unsynchronized motions stacking in the same frame (visible jitter on release). The fix keeps
// the decision here pure and moves the two-stage animation (slide `dragOffset` off-screen, THEN
// dismiss) into `dragGesture.onEnded`.
enum SheetDragReleaseOutcome: Equatable {
    /// Drag exceeded the dismiss threshold: animate `dragOffset` to `targetOffset` (fully
    /// off-screen) along the card's own motion, then — only once that finishes — tell the
    /// container to unmount. By the time `.transition(.move(edge:.bottom))` takes over, the
    /// card is already off-screen, so its motion is invisible (no stacked jitter).
    case dismiss(targetOffset: CGFloat)
    /// Drag released under the threshold: spring the card back to `dragOffset == 0` (sheet stays
    /// open). Unchanged from the pre-existing behavior.
    case bounceBack
}

// MARK: - Content height measurement (rb-ios-product-sheet-resize-fav-inline, extended by
// rb-ios-sheetkit-resize-dismiss-unify)
//
// Background `GeometryReader` reader on `sheetContent()` — deliberately NOT the whole card
// (which also includes `SheetGrabHandle` above it): `LBSheetScaffold.cap` (what
// `heightFractionOverride` drives) represents ONLY `sheetContent()`'s own header+body+footer
// total, with no notion of the handle, so this reader must measure on the SAME basis or the
// very first drag sample would compute a `cap` that's `SheetGrabHandle`'s height too tall,
// jumping `bodyMax` the instant the override goes non-nil (see the `card` computed property's
// comment for the full derivation). Two consumers: (1) latches `BottomSheetChrome.floorFraction`
// — this presentation's resize FLOOR — the first time a real (non-override) height is measured,
// so the presenter never needs to know whether it's hosting a `fillToCap` or content-sized leaf
// (design.md Decision 3); (2) a defensive fallback so a resize gesture's first sample has a real
// "current height" to compute its starting fraction from even if `floorFraction` somehow hasn't
// latched yet. Mirrors the `sheetHeightReader` pattern above; never drives any rendering itself.
private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Chrome (scrim + bottom-anchored card + handle + drag)

/// The visual + gesture chrome shared by every bottom sheet. Renders nothing about WHEN it
/// shows (the modifiers own that); it only draws the scrim + card and forwards `onDismiss`.
struct BottomSheetChrome<SheetContent: View>: View {
    let theme: ReferenceUITheme
    let onDismiss: () -> Void
    @ViewBuilder let sheetContent: () -> SheetContent

    /// Drag-to-dismiss threshold (pt) past which release dismisses; otherwise spring back.
    private static var dismissThreshold: CGFloat { 100 }

    /// Shared height-resize CEILING across every bottom sheet (rb-ios-sheetkit-resize-dismiss-unify)
    /// — dragging the handle UP never grows the card past 90% of the screen, regardless of the
    /// sheet's own default/floor height (see `floorFraction` below). All 5 real bottom sheets
    /// (VideoInfoPanel / ProductList / ProductDetail(`.detail`) / AddToCart / NotifyRestock)
    /// share this one value.
    static var resizeCeilingFraction: CGFloat { 0.90 }

    /// Fallback floor (25%, the pre-unification hardcoded minimum) used ONLY in the practically
    /// unreachable case a drag begins before the card's first layout pass has measured anything
    /// (`floorFraction == nil` AND `measuredCardHeight == 0`). Once the card is on screen —
    /// required for the user to touch its grab handle — `floorFraction` is already latched from
    /// the real measurement (see the `CardHeightKey` `onPreferenceChange` handler below).
    private static var fallbackFloorFraction: CGFloat { 0.25 }

    /// Pure: what a drag release should do, given the released translation and the full
    /// off-screen travel distance. `> dismissThreshold` (strict) matches the pre-existing
    /// threshold semantics bit-for-bit — only the two dismiss-side actions changed (see
    /// `SheetDragReleaseOutcome.dismiss`), not the threshold comparison itself. Extracted for
    /// unit testing (rb-ios-sheet-drag-dismiss-jitter) — call as
    /// `BottomSheetChrome<EmptyView>.dragReleaseOutcome(...)`. Signature / behavior UNCHANGED by
    /// rb-ios-sheetkit-resize-dismiss-unify — only the caller now feeds it
    /// `dragState(...).dragOffset` (the points dragged PAST the resize floor) instead of the raw
    /// gesture translation; the two are numerically identical whenever the user never drags the
    /// sheet taller than its floor this presentation (see `dragState` below).
    static func dragReleaseOutcome(
        translationHeight: CGFloat,
        offscreenDistance: CGFloat
    ) -> SheetDragReleaseOutcome {
        translationHeight > dismissThreshold
            ? .dismiss(targetOffset: offscreenDistance)
            : .bounceBack
    }

    /// Pure: the unified live `(heightFraction, dragOffset)` pair for a continuous handle drag
    /// (rb-ios-sheetkit-resize-dismiss-unify) — replaces the prior TWO independent states (an
    /// up-drag-only `resizedHeightFraction` + a down-drag-only raw `dragOffset`) with ONE state
    /// machine shared by every bottom sheet. `baseFraction` is the fraction in effect when the
    /// CURRENT gesture began (so consecutive drags compose); `floorFraction` is THIS
    /// presentation's own default/resting height (captured once — see the `CardHeightKey`
    /// `onPreferenceChange` handler below); `translationHeight` is the gesture's cumulative
    /// vertical translation (negative = up = taller); `screenHeight` is the reference screen
    /// height.
    ///
    /// The card's fraction tracks `baseFraction - translationHeight/screenHeight`, clamped to
    /// `[floorFraction, resizeCeilingFraction]`; only once dragging DOWN would push the fraction
    /// BELOW `floorFraction` does the excess (in points) show up as `dragOffset` instead — the
    /// two are mutually exclusive at every instant (`dragOffset > 0` implies
    /// `heightFraction == floorFraction`). Guards `screenHeight <= 0` by returning
    /// `(baseFraction, 0)` unchanged (defensive; never hit in practice —
    /// `UIScreen.main.bounds.height` is always positive).
    ///
    /// Equivalence with the pre-unification behavior when the user never drags the sheet taller
    /// than its floor this presentation (`baseFraction == floorFraction`): `dragOffset` reduces
    /// to exactly `max(0, translationHeight)` — the same raw down-drag formula `BottomSheetChrome`
    /// used before this change — so `VideoInfoPanelView` / `ProductListView`, and any sheet the
    /// user simply pulls down without first dragging up, keep the EXACT prior dismiss-threshold
    /// behavior.
    static func dragState(
        baseFraction: CGFloat,
        floorFraction: CGFloat,
        translationHeight: CGFloat,
        screenHeight: CGFloat
    ) -> (heightFraction: CGFloat, dragOffset: CGFloat) {
        guard screenHeight > 0 else { return (baseFraction, 0) }
        let candidate = baseFraction + (-translationHeight / screenHeight)
        let heightFraction = min(resizeCeilingFraction, max(floorFraction, candidate))
        let dragOffset = max(0, floorFraction - candidate) * screenHeight
        return (heightFraction, dragOffset)
    }

    @State private var dragOffset: CGFloat = 0
    /// Live drag-resize result (rb-ios-sheetkit-resize-dismiss-unify). `nil` = the user hasn't
    /// dragged this presentation yet — the leaf's own default cap applies.
    @State private var heightFraction: CGFloat?
    /// The fraction in effect at the START of the CURRENT drag gesture; `nil` between gestures.
    /// Captured once per gesture (first sample), cleared in `onEnded`.
    @State private var resizeBaseFraction: CGFloat?
    /// `sheetContent()`'s last-measured on-screen height (pt) — NOT the whole card, deliberately
    /// EXCLUDING the grab handle above it (fed by `CardHeightKey`, measured on `sheetContent()`
    /// alone; see the `card` computed property's comment for why). Also seeds `floorFraction`
    /// (below) and, defensively, a gesture's base fraction if a drag somehow begins before
    /// `floorFraction` has latched. The `CardHeightKey` reader that feeds this is only mounted
    /// while `floorFraction == nil` (rb-ios-sheet-resize-drag-render-cost-jitter) — once latched,
    /// this value simply stops updating (it has no consumer past that point anyway).
    @State private var measuredCardHeight: CGFloat = 0
    /// This presentation's default/resting height fraction (rb-ios-sheetkit-resize-dismiss-unify)
    /// — the RESIZE FLOOR. Latched ONCE, the first time `sheetContent()`'s real (non-override)
    /// height is measured (see the `CardHeightKey` `onPreferenceChange` handler below); never overwritten
    /// again this presentation, even as subsequent drags change the rendered height via
    /// `heightFraction`. `nil` until that first measurement lands; resets to `nil` on the next
    /// presentation (fresh `@State`, same lifecycle as `heightFraction`).
    @State private var floorFraction: CGFloat?
    /// Whether the resize/dismiss drag gesture is CURRENTLY tracking touch moves
    /// (rb-ios-sheetkit-resize-dismiss-unify) — forwarded to `LBSheetScaffold` via
    /// `lbSheetIsDragging` so it can freeze its own measurements for the gesture's duration (see
    /// the anti-jitter note there). `true` for the span of `dragGesture.onChanged` ...
    /// `.onEnded`; `false` otherwise.
    @State private var isDragging = false

    var body: some View {
        ZStack {
            scrim
                .transition(.opacity)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                card
                    .transition(.move(edge: .bottom))
            }
        }
    }

    // Full-bleed dim scrim — transparent Button (iOS-14-safe; an onTapGesture on a Color
    // renders unreliably headless). Sits above host content → also blocks the video below.
    private var scrim: some View {
        Button(action: onDismiss) {
            Color.black.opacity(0.55)
                .edgesIgnoringSafeArea(.all)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.bottomSheetScrim)
    }

    private var card: some View {
        VStack(spacing: 0) {
            SheetGrabHandle()
                .contentShape(Rectangle())   // whole handle strip is the drag target
                .gesture(dragGesture)
            // The leaf owns its own half-screen cap + body scroll via `LBSheetScaffold`
            // (pinned header/footer, scrollable body — rb-ios-sheet-pinned-header-footer). The
            // presenter only draws the grab handle + card chrome. `heightFraction` (non-nil once
            // the user has dragged this presentation) and `isDragging` are forwarded via
            // environment so the leaf's `LBSheetScaffold` can override its own cap and freeze its
            // measurements while dragging (rb-ios-sheetkit-resize-dismiss-unify).
            //
            // `CardHeightKey` is measured HERE — on `sheetContent()` alone, NOT the outer VStack
            // — because `LBSheetScaffold.cap` (what `heightFractionOverride` ultimately drives)
            // represents ONLY `sheetContent()`'s own total height (header + body + footer); it
            // has no notion of the grab handle above it. Measuring the whole card (handle +
            // content) would fold `SheetGrabHandle`'s fixed ~16pt (8pt top padding + 4pt pill +
            // 4pt bottom padding) into `floorFraction`, so the very FIRST drag sample — even at
            // ~0 net translation — would compute a `cap` ~16pt taller than the sheet's actual
            // pre-drag content height, and `bodyMax` would jump by that amount the instant
            // `heightFractionOverride` goes non-nil (content-sized → fill-to-cap). Scoping the
            // reader to `sheetContent()` keeps `floorFraction` and `cap` on the SAME basis as
            // `LBSheetScaffold`'s own header/body/footer measurements, so the mode switch lands
            // on the identical pixel height (design.md Decision 4). Note:
            // `testFloorFraction_derivedFromSheetContentHeightOnly_reproducesPreDragBodyHeightWithoutJump`
            // only checks the arithmetic identity `cap - headerH - footerH == bodyH`; it does not
            // mount `BottomSheetChrome` and so cannot by itself catch the reader being moved back
            // onto the outer `VStack` — this comment's claim rests on the reader being attached
            // here, not on that test.
            //
            // The reader is only MOUNTED while `floorFraction == nil` (rb-ios-sheet-resize-drag-
            // render-cost-jitter) — once latched, `measuredCardHeight`'s post-latch value has no
            // consumer at all (`dragGesture.onChanged`'s `floor` fallback — `measuredCardHeight >
            // 0 ? ... : fallbackFloorFraction` — is dead once `floorFraction` is non-nil, since
            // `floorFraction ?? ...` short-circuits first), so continuing to re-measure after
            // latch was pure waste: a `GeometryReader` layout pass on every touch-move sample of
            // EVERY subsequent drag this presentation, for a value nothing reads. Unmounting it
            // removes that cost outright, not just its (already-discarded) result.
            sheetContent()
                .environment(\.lbSheetHeightFractionOverride, heightFraction)
                .environment(\.lbSheetIsDragging, isDragging)
                .background(sheetHeightReader(CardHeightKey.self, active: floorFraction == nil))
                .onPreferenceChange(CardHeightKey.self) { newHeight in
                    measuredCardHeight = newHeight
                    // Latch the RESIZE FLOOR once, the first time we see a real (positive)
                    // measurement — this is "the height `sheetContent()` actually rendered at,
                    // before any drag" for EVERY leaf kind (a `fillToCap` leaf measures its
                    // fixed cap; a content-sized leaf measures its natural content height), so
                    // the presenter never needs to know which kind of leaf it's hosting
                    // (rb-ios-sheetkit-resize-dismiss-unify, design.md Decision 3). This is the
                    // ONLY write this preference will ever deliver once it fires — the reader
                    // above unmounts itself the next time `body` is evaluated after `floorFraction`
                    // becomes non-nil.
                    if floorFraction == nil, newHeight > 0 {
                        floorFraction = newHeight / UIScreen.main.bounds.height
                    }
                }
        }
        .background(theme.background)
        .clipShape(TopRoundedRectangle(radius: 20))
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: -4)
        .offset(y: max(0, dragOffset))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                let screenHeight = UIScreen.main.bounds.height
                let floor = floorFraction
                    ?? (measuredCardHeight > 0 ? measuredCardHeight / screenHeight : Self.fallbackFloorFraction)
                let base = resizeBaseFraction ?? heightFraction ?? floor
                if resizeBaseFraction == nil { resizeBaseFraction = base }
                let state = Self.dragState(
                    baseFraction: base,
                    floorFraction: floor,
                    translationHeight: value.translation.height,
                    screenHeight: screenHeight)
                heightFraction = state.heightFraction
                dragOffset = state.dragOffset
            }
            .onEnded { _ in
                isDragging = false
                resizeBaseFraction = nil   // always clear — the next gesture starts fresh
                switch Self.dragReleaseOutcome(
                    translationHeight: dragOffset,
                    offscreenDistance: UIScreen.main.bounds.height
                ) {
                case .dismiss(let targetOffset):
                    // Slide the card the rest of the way off-screen along the SAME motion the
                    // user's finger was already driving (no independent transition kicking in
                    // mid-gesture), THEN — only once that finishes — unmount the container. This
                    // is what prevents the release-time jitter (rb-ios-sheet-drag-dismiss-jitter).
                    withAnimation(sheetSlide) {
                        dragOffset = targetOffset
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + sheetSlideDuration) {
                        onDismiss()
                    }
                case .bounceBack:
                    // `dragOffset == 0` here means the gesture never pushed the height past the
                    // floor (pure resize, up OR down) — the resulting `heightFraction` is KEPT
                    // as-is; this animation is then a harmless no-op (nothing to spring back).
                    // `dragOffset > 0` but under threshold means the sheet was already at the
                    // floor and the user peeked past it without reaching the dismiss threshold —
                    // spring the peek back to 0 (sheet rests at its floor height).
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }
}
