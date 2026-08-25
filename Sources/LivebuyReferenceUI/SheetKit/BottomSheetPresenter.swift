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
// `BottomSheetChrome` (the presenter) measures the UP-drag (resize) gesture and computes a live
// height FRACTION; `LBSheetScaffold` (the leaf) is what actually computes `cap` / drives the body
// frame. This environment key is the one channel between them: `BottomSheetChrome` sets it
// (non-nil) once the user has dragged the handle UP at least once during the CURRENT
// presentation; `nil` (the default) means "no override — use the leaf's own `capFraction` /
// `fillToCap`". EVERY `.lbBottomSheet(...)` call site (both the `isPresented:` and `item:`
// overloads) can set this to non-nil — the resize gesture is universal across all 5 real bottom
// sheets, not an opt-in limited to the product-sheet stack. The DOWN-drag (dismiss) gesture never
// touches this key at all (see `BottomSheetChrome.dragGesture` below —
// rb-ios-sheetkit-resize-dismiss-separate-gestures).
private struct SheetHeightFractionOverrideKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var lbSheetHeightFractionOverride: CGFloat? {
        get { self[SheetHeightFractionOverrideKey.self] }
        set { self[SheetHeightFractionOverrideKey.self] = newValue }
    }
}

// MARK: - Resize-in-progress signal (rb-ios-sheetkit-resize-dismiss-separate-gestures, originally
// `lbSheetIsDragging` from rb-ios-sheetkit-resize-dismiss-unify)
//
// `LBSheetScaffold` reads this to FREEZE its header/footer/body `GeometryReader` measurements
// while the UP-drag (resize) branch of `dragGesture` is actively tracking touch moves (see the
// anti-jitter note on `LBSheetScaffold`'s `onPreferenceChange` handlers below). `BottomSheetChrome`
// sets it `true` only for the span of the RESIZE branch (`onChanged` when `translation.height < 0`
// ... `onEnded`) — the DOWN-drag (dismiss) branch never sets this `true`: a dismiss drag never
// touches `lbSheetHeightFractionOverride`, so it never triggers the `LBSheetScaffold` re-layout
// feedback loop this freeze exists to prevent (see `dragGesture` below — the two branches are
// independent judgments that share no live calculation, only the `translation.height` sign that
// routes between them).
private struct SheetIsResizingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var lbSheetIsResizing: Bool {
        get { self[SheetIsResizingKey.self] }
        set { self[SheetIsResizingKey.self] = newValue }
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
    /// Whether the UP-drag (resize) branch of the handle gesture is CURRENTLY tracking touch
    /// moves (rb-ios-sheetkit-resize-dismiss-separate-gestures) — see the anti-jitter note on the
    /// `onPreferenceChange` handlers below. Never set `true` by the DOWN-drag (dismiss) branch.
    @Environment(\.lbSheetIsResizing) private var isResizing

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
                header().background(sheetHeightReader(SheetHeaderHeightKey.self, active: !isResizing))
                ScrollView {
                    bodyContent().background(sheetHeightReader(SheetContentHeightKey.self, active: !isResizing))
                }
                // `effectiveFillToCap`（`fillToCap` 或使用者已拖曳出高度覆寫）：固定填滿到 bodyMax
                // （content 頂部對齊、下方留白 / 超出捲動）→ sheet 固定 = cap。否則 content-sized（既有行為）。
                .frame(height: effectiveFillToCap ? bodyMax : (bodyH <= 0 ? bodyMax : min(bodyH, bodyMax)))
                footer().background(sheetHeightReader(SheetFooterHeightKey.self, active: !isResizing))
            }
            // Anti-jitter freeze (rb-ios-sheetkit-resize-dismiss-unify, hardened by
            // rb-ios-sheet-resize-drag-render-cost-jitter, rescoped to the UP-drag/resize branch
            // ONLY by rb-ios-sheetkit-resize-dismiss-separate-gestures — the DOWN-drag/dismiss
            // branch never sets `isResizing == true`, since dismiss never touches
            // `heightFractionOverride` and therefore never triggers the feedback loop this freeze
            // exists to prevent): while the resize branch is actively tracking touch moves
            // (`isResizing == true`), these three `GeometryReader`s are UNMOUNTED entirely (see the
            // `active:` overload of `sheetHeightReader` above) — not merely present-but-ignored.
            // The original fix (guarding the `onPreferenceChange` write below with `if
            // !isResizing`) only stopped the *result* from reaching `@State`; the
            // `GeometryReader`s themselves kept re-running their layout-measurement pass on every
            // touch-move sample regardless, a real per-frame cost (3 readers here + one more in
            // `BottomSheetChrome.card` for the resize floor) that could miss a frame budget and
            // show up as a persistent stutter during the drag itself — most visible on slow drags,
            // where the same-size hitch is a larger fraction of the expected per-frame motion.
            // Unmounting removes that cost outright. `cap` / `bodyMax` recompute from a FROZEN
            // header/footer pair instead, driven purely by `heightFractionOverride` (no round trip
            // through this scaffold's own layout). Measurement resumes immediately once the resize
            // gesture ends (`isResizing` flips back to `false`, remounting the readers), so content
            // that changes BETWEEN gestures (e.g. the add-to-cart CTA spinner altering footer
            // height) is still picked up correctly. The `if !isResizing` guards below are kept as a
            // defensive no-op belt-and-braces — they should never fire while unmounted, since an
            // unmounted `GeometryReader` reports no preference at all.
            .onPreferenceChange(SheetHeaderHeightKey.self) { if !isResizing { headerH = $0 } }
            .onPreferenceChange(SheetFooterHeightKey.self) { if !isResizing { footerH = $0 } }
            .onPreferenceChange(SheetContentHeightKey.self) { if !isResizing { bodyH = $0 } }
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
//   • drag-to-resize (UP) + drag-to-dismiss (DOWN) on the HANDLE strip as TWO STRUCTURALLY
//     INDEPENDENT judgments (rb-ios-sheetkit-resize-dismiss-separate-gestures), routed purely by
//     the sign of `value.translation.height` at each touch sample — replacing the prior
//     `rb-ios-sheetkit-resize-dismiss-unify` design, which computed BOTH through one shared pure
//     function (`dragState`) and one shared freeze flag every touch sample regardless of
//     direction. That shared state machine needed 3 follow-up jitter-fix rounds, and every one of
//     those rounds' own root-cause diagnosis says the jitter "only happens during up-drag
//     resize" — dismiss was never the source, yet was forced to share the same machinery.
//       - UP-drag (resize): the sheet content's height FLOOR is THIS presentation's own
//         default/resting height (`floorFraction`, latched once from the first real measurement
//         of `sheetContent()` alone — see `CardHeightKey` below), the CEILING is a shared
//         `resizeCeilingFraction` (90%) across all 5 real bottom sheets. Dragging UP grows the
//         height toward the ceiling, clamped at the floor on the low end. Driven by the pure
//         function `resizedHeightFraction(...)` — see below.
//       - DOWN-drag (dismiss): BYTE-FOR-BYTE independent of the resize branch — reads none of
//         `heightFraction` / `floorFraction` / `resizeBaseFraction`. `dragOffset` is exactly
//         `max(0, translation.height)`; past the 100pt threshold on release, dismiss (via the
//         unchanged `dragReleaseOutcome(...)`); otherwise bounce back to 0. This is exactly the
//         `rb-ios-sheet-drag-dismiss-jitter` logic, predating even `rb-ios-sheetkit-resize-
//         dismiss-unify` — restored verbatim, not re-derived.
//   • scrim `.opacity` + card `.move(edge:.bottom)` enter/exit transitions.
//   • Anti-jitter freeze while the UP-drag (resize) branch is tracking touch moves — SCOPED to
//     resize only, never triggered by a dismiss drag (`rb-ios-sheetkit-resize-dismiss-unify`,
//     hardened by `rb-ios-sheet-resize-drag-render-cost-jitter` and
//     `rb-ios-sheet-drag-render-drawinggroup`, rescoped by
//     `rb-ios-sheetkit-resize-dismiss-separate-gestures`): `LBSheetScaffold` UNMOUNTS its
//     header/footer/body `GeometryReader`s entirely for the resize gesture's duration
//     (`lbSheetIsResizing` environment key) — not merely discards their result — breaking BOTH
//     the one-frame-behind feedback loop that produced the original visible jitter (resize
//     changing `heightFraction` on every touch move) AND the ongoing per-frame layout-measurement
//     COST of four live `GeometryReader`s during a resize drag, which could miss a frame budget
//     and show up as a persistent stutter through the drag itself (most visible on slow drags).
//     `BottomSheetChrome.card`'s own `CardHeightKey` reader is similarly unmounted once
//     `floorFraction` latches, since nothing consumes it past that point anyway.
//     `BottomSheetChrome.card` also flattens itself via `.drawingGroup()` during a resize drag
//     (see `cardSurface`), gated to `isResizing == true` only, so `.shadow()` shadows one
//     pre-rendered layer per touch sample instead of the whole card subtree — a compositing-cost
//     dimension the GeometryReader-unmount fix never touched. This is a code-reading-driven
//     hypothesis with no Instruments/on-device frame-rate profiling behind it; whether it
//     actually fixes user-visible jitter needs manual Simulator/device confirmation (see
//     `rb-ios-sheetkit-resize-dismiss-separate-gestures`'s design.md Non-Goals — this change does
//     not re-litigate whether the resize branch's own jitter is fully fixed, only that dismiss no
//     longer shares its machinery).
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
    /// `BottomSheetChrome.dragGesture` for the two independent branches
    /// (rb-ios-sheetkit-resize-dismiss-separate-gestures).
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
    /// `BottomSheetChrome<EmptyView>.dragReleaseOutcome(...)`. Signature / behavior UNCHANGED
    /// across every change that has touched this file — `rb-ios-sheetkit-resize-dismiss-unify`
    /// briefly routed it through the merged `dragState(...).dragOffset`;
    /// `rb-ios-sheetkit-resize-dismiss-separate-gestures` reverted the CALLER back to feeding it
    /// the raw dismiss-branch gesture translation directly (see `dragGesture` below) — this
    /// function itself was never touched by either change.
    static func dragReleaseOutcome(
        translationHeight: CGFloat,
        offscreenDistance: CGFloat
    ) -> SheetDragReleaseOutcome {
        translationHeight > dismissThreshold
            ? .dismiss(targetOffset: offscreenDistance)
            : .bounceBack
    }

    /// Pure: the live height fraction for the UP-drag (resize) branch of a continuous handle drag
    /// (rb-ios-sheetkit-resize-dismiss-separate-gestures — the resize-only half of what used to
    /// be the merged `dragState(...)`; the dismiss half is no longer computed by any shared
    /// function, see `dragGesture` below). `baseFraction` is the fraction in effect when the
    /// CURRENT gesture began (so consecutive drags compose); `floorFraction` is THIS
    /// presentation's own default/resting height (captured once — see the `CardHeightKey`
    /// `onPreferenceChange` handler below, NOT a fixed constant — see `fallbackFloorFraction`'s
    /// doc comment for why a fixed floor was a known defect of the pre-unification design);
    /// `translationHeight` is the gesture's cumulative vertical translation (negative = up =
    /// taller); `screenHeight` is the reference screen height.
    ///
    /// The card's fraction tracks `baseFraction - translationHeight/screenHeight`, clamped to
    /// `[floorFraction, resizeCeilingFraction]`. Guards `screenHeight <= 0` by returning
    /// `baseFraction` unchanged (defensive; never hit in practice —
    /// `UIScreen.main.bounds.height` is always positive).
    static func resizedHeightFraction(
        baseFraction: CGFloat,
        floorFraction: CGFloat,
        translationHeight: CGFloat,
        screenHeight: CGFloat
    ) -> CGFloat {
        guard screenHeight > 0 else { return baseFraction }
        let candidate = baseFraction + (-translationHeight / screenHeight)
        return min(resizeCeilingFraction, max(floorFraction, candidate))
    }

    @State private var dragOffset: CGFloat = 0
    /// Live drag-resize result (rb-ios-sheetkit-resize-dismiss-unify), written ONLY by the
    /// UP-drag (resize) branch of `dragGesture`. `nil` = the user hasn't dragged UP this
    /// presentation yet — the leaf's own default cap applies.
    @State private var heightFraction: CGFloat?
    /// The fraction in effect at the START of the CURRENT resize gesture; `nil` between resize
    /// gestures. Captured once per resize gesture (first up-drag sample), cleared in `onEnded`.
    /// Never touched by the dismiss branch.
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
    /// Whether the UP-drag (resize) branch of the handle gesture is CURRENTLY tracking touch
    /// moves (rb-ios-sheetkit-resize-dismiss-separate-gestures) — forwarded to `LBSheetScaffold`
    /// via `lbSheetIsResizing` so it can freeze its own measurements for the resize gesture's
    /// duration (see the anti-jitter note there). `true` only for the span of the resize branch
    /// (`dragGesture.onChanged` when `translation.height < 0` ... `.onEnded`); the DOWN-drag
    /// (dismiss) branch never sets this `true` — it has no reason to, since dismiss never touches
    /// `lbSheetHeightFractionOverride`.
    @State private var isResizing = false

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
        cardSurface
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: -4)
            .offset(y: max(0, dragOffset))
    }

    // MARK: - Drag-time compositing flatten (rb-ios-sheet-drag-render-drawinggroup, round 4)
    //
    // round-3 (rb-ios-sheet-resize-drag-render-cost-jitter) unmounted the header/footer/body/
    // CardHeightKey `GeometryReader`s during a drag, on the hypothesis that their layout-
    // measurement pass — even with its result discarded — was the persistent, touch-sample-rate
    // cost behind the "stutter, more visible on slow drags" symptom. The user re-tested on device
    // afterward and the jitter did NOT go away (if anything, worse) — that hypothesis is
    // disproved or at least not the (sole) root cause. round-3's own design.md had already named
    // `.drawingGroup()` as the next candidate and recorded why it was deferred at the time (risk
    // to `sheetContent()`'s interactive subviews' hit-testing, and to the snapshot
    // `ImageRenderer` path) — this round revisits that call now that the user has confirmed they
    // want it.
    //
    // `.drawingGroup()` flattens everything ABOVE it in the modifier chain into one Metal-backed
    // offscreen layer. Placed here — after `.clipShape(...)`, before `.shadow(...)` in `card` —
    // it means `.shadow()` only has to shadow ONE flattened layer per re-render instead of
    // shadowing every descendant of the `VStack` individually (SwiftUI's default behavior for
    // `.shadow()` on a compound subtree with no prior flatten: each leaf view that draws
    // something gets its own shadow pass, composited separately). `card`'s `body` is forced to
    // re-evaluate on EVERY touch-move sample during a drag (`dragOffset` / `heightFraction`
    // changing), so that per-sample shadow/compositing cost is exactly the kind of
    // touch-sample-rate-proportional persistent cost the "slow drag more visible" symptom
    // fingerprints — a DIFFERENT dimension from round-3's layout-measurement cost, untouched by
    // that fix. `.offset(y:)` stays OUTSIDE (after) this, in `card` above — it's a cheap pure
    // layout translation of the already-flattened layer, not something that needs flattening
    // itself.
    //
    // Gated to `isResizing == true` only (not resident, and — since
    // rb-ios-sheetkit-resize-dismiss-separate-gestures — never true for a dismiss drag either,
    // only the UP-drag/resize branch) — three reasons:
    //   1. Structural snapshot safety: the `.lbSheetHeightUncapped` `ImageRenderer` snapshot path
    //      never simulates a gesture (round-3 design.md confirmed this), so `isResizing` is
    //      always `false` there — `.drawingGroup()` never mounts on that path BY CONSTRUCTION,
    //      not merely "in practice", so baselines are guaranteed byte-identical without needing
    //      re-verification of `.drawingGroup()`'s own rendering fidelity under `ImageRenderer`.
    //   2. Resting-state fidelity: `.drawingGroup()` rasterizes via Metal, which carries a small
    //      theoretical risk of subtly different text antialiasing vs. native Core Animation
    //      layer compositing. Scoping it to the drag window keeps the sheet's resting/static
    //      appearance (the vast majority of a sheet's on-screen time) on the exact same rendering
    //      path as before this change.
    //   3. Hit-testing: re-examined round-3's deferral reason — SwiftUI hit-testing is driven by
    //      view geometry (frames), not by the rasterized pixel output `.drawingGroup()` produces;
    //      flattening a subtree's DRAWING does not change its hit-testing coordinate space, so
    //      buttons / `ScrollView` / gesture recognizers inside `sheetContent()` are expected to
    //      keep responding normally. That said, this expectation rests on documented SwiftUI
    //      behavior, not on an actual touch test on a real device (none attached to this dev
    //      machine) — gating to the drag window keeps this untested assumption's exposure limited
    //      to the span a user's finger is on the grab handle (not generally poking buttons inside
    //      the sheet at the same time), rather than the card's entire lifetime.
    //
    // See design.md "Decisions" §1–2 for the full write-up, including what to try next if this
    // round's hypothesis also turns out wrong (widen to resident, or narrow the flattened scope).
    @ViewBuilder
    private var cardSurface: some View {
        let surface = cardContent
            .background(theme.background)
            .clipShape(TopRoundedRectangle(radius: 20))
        if isResizing {
            surface.drawingGroup()
        } else {
            surface
        }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            SheetGrabHandle()
                .contentShape(Rectangle())   // whole handle strip is the drag target
                .gesture(dragGesture)
            // The leaf owns its own half-screen cap + body scroll via `LBSheetScaffold`
            // (pinned header/footer, scrollable body — rb-ios-sheet-pinned-header-footer). The
            // presenter only draws the grab handle + card chrome. `heightFraction` (non-nil once
            // the user has dragged UP this presentation) and `isResizing` are forwarded via
            // environment so the leaf's `LBSheetScaffold` can override its own cap and freeze its
            // measurements while the RESIZE branch is dragging (rb-ios-sheetkit-resize-dismiss-
            // unify, rescoped to resize-only by rb-ios-sheetkit-resize-dismiss-separate-gestures).
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
                .environment(\.lbSheetIsResizing, isResizing)
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
    }

    // MARK: - Drag gesture (rb-ios-sheetkit-resize-dismiss-separate-gestures)
    //
    // Two structurally INDEPENDENT branches, routed purely by the sign of the CURRENT touch
    // sample's `translation.height` — mirrors the pre-`rb-ios-sheetkit-resize-dismiss-unify`
    // structure. The resize branch never reads `dragOffset` (beyond resetting it to 0 when it
    // takes over, discarding a same-gesture down-peek that reversed upward past 0); the dismiss
    // branch never reads `heightFraction` / `floorFraction` / `resizeBaseFraction` at all — the
    // two share no live calculation, only this routing decision.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard value.translation.height < 0 else {
                    // DISMISS branch — byte-for-byte the pre-rb-ios-sheetkit-resize-dismiss-unify
                    // down-drag logic (rb-ios-sheet-drag-dismiss-jitter): the raw translation IS
                    // the peek offset, full stop. No floor, no ceiling, no resize state consulted.
                    isResizing = false
                    dragOffset = max(0, value.translation.height)
                    return
                }
                // RESIZE branch — dragging UP grows the card toward the shared 90% ceiling from
                // THIS presentation's own floor (its default/resting height, latched once — see
                // `CardHeightKey` above). Discards any partial down-peek `dragOffset` this same
                // continuous gesture may have accrued before reversing upward past 0, so the two
                // mutually-exclusive visual effects (offset vs. live height) never combine.
                isResizing = true
                dragOffset = 0
                let screenHeight = UIScreen.main.bounds.height
                let floor = floorFraction
                    ?? (measuredCardHeight > 0 ? measuredCardHeight / screenHeight : Self.fallbackFloorFraction)
                let base = resizeBaseFraction ?? heightFraction ?? floor
                if resizeBaseFraction == nil { resizeBaseFraction = base }
                heightFraction = Self.resizedHeightFraction(
                    baseFraction: base,
                    floorFraction: floor,
                    translationHeight: value.translation.height,
                    screenHeight: screenHeight)
            }
            .onEnded { value in
                isResizing = false
                resizeBaseFraction = nil   // always clear — the next gesture starts fresh
                // Released while the gesture's NET translation was still upward (resize): the
                // resized height is KEPT as-is (no snap-back, no dismiss check) — matches the
                // pre-rb-ios-sheetkit-resize-dismiss-unify `guard value.translation.height >= 0
                // else { return }`. `dragOffset` is guaranteed 0 here (the resize branch above
                // always resets it), so there's nothing to animate even if this guard weren't here.
                guard value.translation.height >= 0 else { return }
                switch Self.dragReleaseOutcome(
                    translationHeight: value.translation.height,
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
                    // Released under the 100pt threshold while net-downward (or exactly at 0):
                    // spring the peek back to 0 (sheet rests at its current height).
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }
}
