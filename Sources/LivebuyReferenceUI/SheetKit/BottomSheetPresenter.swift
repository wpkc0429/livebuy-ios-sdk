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

// MARK: - Drag-resize height override (rb-ios-product-sheet-resize-fav-inline)
//
// `BottomSheetChrome` (the presenter) measures the drag and computes a live height FRACTION;
// `LBSheetScaffold` (the leaf) is what actually computes `cap` / drives the body frame. This
// environment key is the one channel between them: `BottomSheetChrome` sets it (non-nil) once
// the user has dragged the handle UP at least once during the CURRENT presentation; `nil` (the
// default) means "no override — use the leaf's own `capFraction` / `fillToCap`". Only the
// `.lbBottomSheet(item:)` overload's `resizable: true` opt-in ever sets this to non-nil; the
// `isPresented:` overload (VideoInfoPanel / ProductListView) never touches it, so those leaves
// are byte-identical to before this key existed.
private struct SheetHeightFractionOverrideKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var lbSheetHeightFractionOverride: CGFloat? {
        get { self[SheetHeightFractionOverrideKey.self] }
        set { self[SheetHeightFractionOverrideKey.self] = newValue }
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
    /// Live drag-resize override (rb-ios-product-sheet-resize-fav-inline), set by
    /// `BottomSheetChrome` only when `resizable == true` AND the user has dragged the handle up
    /// during the current presentation. `nil` (the default — every leaf except the product-sheet
    /// family, and even those before the first drag) → this scaffold's own `fillToCap` /
    /// `capFraction` decide `cap`, unaffected.
    @Environment(\.lbSheetHeightFractionOverride) private var heightFractionOverride

    /// `true` → 固定高度填滿到 cap（content 頂部對齊、footer 釘底、不足處下方留白、超出則捲動），
    /// body-fill 行為對齊設計稿；cap 固定 0.4 螢幕（rb-ios-compact-sheet-cap-and-footer；原
    /// rb-ios-addtocart-sheet-height-align-restock 為設計 `min(drawerH, 70%)` 的 0.7，已由產品覆蓋）。
    /// `false`（預設）→ content-sized（既有行為），cap 改讀 `capFraction`。snapshot（`uncapped`）
    /// 路徑不受此旗標影響。宣告於三個 `@ViewBuilder` 閉包之前，使多重 trailing-closure call site 仍可用。
    var fillToCap: Bool = false
    /// The non-`fillToCap` cap fraction (screen-height multiplier) for THIS instance
    /// (rb-ios-product-sheet-resize-fav-inline). Defaults to `0.5` — the pre-existing value used
    /// by `VideoInfoPanelView` / `ProductListView` / historical `ProductDetailSheetView.detail` —
    /// so every caller that doesn't pass this explicitly is unaffected. `ProductDetailSheetView`'s
    /// `.detail` presentation passes `0.9` explicitly (see design.md), aligned with the new
    /// drag-resize ceiling. Ignored when `fillToCap == true` (that branch always uses `0.4`).
    var capFraction: CGFloat = 0.5

    @ViewBuilder var header: () -> Header
    @ViewBuilder var bodyContent: () -> BodyContent
    @ViewBuilder var footer: () -> Footer

    @State private var headerH: CGFloat = 0
    @State private var footerH: CGFloat = 0
    @State private var bodyH: CGFloat = 0

    /// `fillToCap` sheet 固定 0.4 螢幕高（精簡購買 / 補貨 sheet 的產品指定高度，覆蓋設計
    /// `min(drawerH, 70%)`；rb-ios-compact-sheet-cap-and-footer）；一般 sheet 維持 `capFraction`
    /// （預設 0.5）。使用者拖曳出的 `heightFractionOverride`（非 nil 時）整段取代這兩者
    /// （rb-ios-product-sheet-resize-fav-inline）。
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
                header().background(sheetHeightReader(SheetHeaderHeightKey.self))
                ScrollView {
                    bodyContent().background(sheetHeightReader(SheetContentHeightKey.self))
                }
                // `effectiveFillToCap`（`fillToCap` 或使用者已拖曳出高度覆寫）：固定填滿到 bodyMax
                // （content 頂部對齊、下方留白 / 超出捲動）→ sheet 固定 = cap。否則 content-sized（既有行為）。
                .frame(height: effectiveFillToCap ? bodyMax : (bodyH <= 0 ? bodyMax : min(bodyH, bodyMax)))
                footer().background(sheetHeightReader(SheetFooterHeightKey.self))
            }
            .onPreferenceChange(SheetHeaderHeightKey.self) { headerH = $0 }
            .onPreferenceChange(SheetFooterHeightKey.self) { footerH = $0 }
            .onPreferenceChange(SheetContentHeightKey.self) { bodyH = $0 }
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
//   • drag-to-dismiss bound to the HANDLE strip only (D-2/D-4): track `translation.height`,
//     follow with `.offset`, and on release past a threshold dismiss, else spring back.
//   • scrim `.opacity` + card `.move(edge:.bottom)` enter/exit transitions.
//   • OPT-IN drag-to-RESIZE (rb-ios-product-sheet-resize-fav-inline, `.lbBottomSheet(item:
//     resizable: true)` only — the product-sheet stack): dragging the handle UP live-resizes
//     the card's height (25%–90% of screen), completely separate `@State` from the down-drag
//     dismiss path above, so the two never interfere. `.lbBottomSheet(isPresented:)` (VideoInfoPanel
//     / ProductListView) never opts in and is byte-identical to before this capability existed.
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
    /// `resizable` (rb-ios-product-sheet-resize-fav-inline, default `false`): when `true`, dragging
    /// the handle UP live-resizes the card (25%–90% of screen height); dragging DOWN is completely
    /// unaffected (same `dragOffset` / `dragReleaseOutcome` dismiss-or-bounce path as always). Only
    /// the product-sheet stack (`ProductSheetsOverlayView`) passes `true`; leave the default `false`
    /// for any other future `item:` caller.
    func lbBottomSheet<Item: Identifiable, SheetContent: View>(
        theme: ReferenceUITheme,
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        resizable: Bool = false,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(BottomSheetItemModifier(
            theme: theme, item: item, onDismiss: onDismiss, resizable: resizable, sheetContent: content))
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
    /// Opt-in drag-resize (rb-ios-product-sheet-resize-fav-inline). Default `false` — only the
    /// product-sheet stack call site passes `true`.
    var resizable: Bool = false
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
         resizable: Bool = false,
         @ViewBuilder sheetContent: @escaping (Item) -> SheetContent) {
        self.theme = theme
        self._item = item
        self.onDismiss = onDismiss
        self.resizable = resizable
        self.sheetContent = sheetContent
        self._presented = State(initialValue: item.wrappedValue != nil)
        self._displayItem = State(initialValue: item.wrappedValue)
    }

    func body(content: Content) -> some View {
        ZStack {
            content
            if presented, let shown = displayItem {
                BottomSheetChrome(theme: theme, onDismiss: dismiss, resizable: resizable) { sheetContent(shown) }
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

// MARK: - Card height measurement (rb-ios-product-sheet-resize-fav-inline)
//
// Background `GeometryReader` reader on the card, so a resize-drag's FIRST sample has a real
// "current height" to compute its starting fraction from (rather than guessing the leaf's cap).
// Mirrors the `sheetHeightReader` pattern above. Read only when a resize gesture begins; never
// drives any rendering itself.
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
    /// Opt-in drag-resize (rb-ios-product-sheet-resize-fav-inline). Default `false` — every
    /// caller except the product-sheet stack's `.lbBottomSheet(item:)` call site.
    var resizable: Bool = false
    @ViewBuilder let sheetContent: () -> SheetContent

    /// Drag-to-dismiss threshold (pt) past which release dismisses; otherwise spring back.
    private static var dismissThreshold: CGFloat { 100 }

    /// Pure: what a drag release should do, given the released translation and the full
    /// off-screen travel distance. `> dismissThreshold` (strict) matches the pre-existing
    /// threshold semantics bit-for-bit — only the two dismiss-side actions changed (see
    /// `SheetDragReleaseOutcome.dismiss`), not the threshold comparison itself. Extracted for
    /// unit testing (rb-ios-sheet-drag-dismiss-jitter) — call as
    /// `BottomSheetChrome<EmptyView>.dragReleaseOutcome(...)`.
    static func dragReleaseOutcome(
        translationHeight: CGFloat,
        offscreenDistance: CGFloat
    ) -> SheetDragReleaseOutcome {
        translationHeight > dismissThreshold
            ? .dismiss(targetOffset: offscreenDistance)
            : .bounceBack
    }

    /// Pure: the new height fraction while dragging the handle UP to resize
    /// (rb-ios-product-sheet-resize-fav-inline). `baseFraction` is the fraction in effect when
    /// this drag gesture began (current card height / screen height); `translationHeight` is the
    /// gesture's cumulative vertical translation (negative = up = taller). Clamped to the
    /// design's resize range (`LBP_SHEET_MIN_H`–`LBP_SHEET_MAX_H`, 25%–90%). Guards
    /// `screenHeight <= 0` by returning `baseFraction` unchanged (defensive; never hit in
    /// practice — `UIScreen.main.bounds.height` is always positive).
    static func resizedHeightFraction(
        baseFraction: CGFloat,
        translationHeight: CGFloat,
        screenHeight: CGFloat
    ) -> CGFloat {
        guard screenHeight > 0 else { return baseFraction }
        let candidate = baseFraction + (-translationHeight / screenHeight)
        return min(0.90, max(0.25, candidate))
    }

    @State private var dragOffset: CGFloat = 0
    /// Live drag-resize result (rb-ios-product-sheet-resize-fav-inline). `nil` = the user hasn't
    /// dragged up yet this presentation — the leaf's own default cap applies. Set only when
    /// `resizable == true`; never touched otherwise, so non-resizable callers are unaffected.
    @State private var heightFraction: CGFloat?
    /// The fraction in effect at the START of the CURRENT resize drag gesture; `nil` between
    /// gestures. Captured once per gesture (first "up" sample), cleared in `onEnded`.
    @State private var resizeBaseFraction: CGFloat?
    /// The card's last-measured on-screen height (pt), fed by `CardHeightKey`. Consulted only to
    /// seed `resizeBaseFraction` when a resize gesture begins for the first time this
    /// presentation (before any `heightFraction` exists yet).
    @State private var measuredCardHeight: CGFloat = 0

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
            // presenter only draws the grab handle + card chrome. `heightFraction` (non-nil only
            // when `resizable` and the user has dragged) is forwarded via environment so the
            // leaf's `LBSheetScaffold` can override its own cap (rb-ios-product-sheet-resize-fav-inline).
            sheetContent()
                .environment(\.lbSheetHeightFractionOverride, heightFraction)
        }
        .background(theme.background)
        .background(sheetHeightReader(CardHeightKey.self))
        .onPreferenceChange(CardHeightKey.self) { measuredCardHeight = $0 }
        .clipShape(TopRoundedRectangle(radius: 20))
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: -4)
        .offset(y: max(0, dragOffset))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Dragging UP (negative translation) while `resizable` live-resizes the card;
                // this is a SEPARATE state (`heightFraction`) from `dragOffset` and never sets
                // it, so it cannot interact with the dismiss/bounce path below
                // (rb-ios-product-sheet-resize-fav-inline). Dragging DOWN (or `!resizable`) is
                // the pre-existing `dragOffset` path, completely unchanged.
                guard resizable, value.translation.height < 0 else {
                    dragOffset = max(0, value.translation.height)
                    return
                }
                // Entering (or continuing) the resize branch always keeps `dragOffset` at 0 — if
                // this same continuous gesture had earlier been dragging DOWN (peek-offset) before
                // reversing upward past 0, that partial peek offset is discarded so the two
                // mutually-exclusive visual effects (offset vs. live height) never combine.
                dragOffset = 0
                let base = resizeBaseFraction
                    ?? heightFraction
                    ?? (measuredCardHeight / UIScreen.main.bounds.height)
                if resizeBaseFraction == nil { resizeBaseFraction = base }
                heightFraction = Self.resizedHeightFraction(
                    baseFraction: base,
                    translationHeight: value.translation.height,
                    screenHeight: UIScreen.main.bounds.height)
            }
            .onEnded { value in
                resizeBaseFraction = nil   // always clear — the next gesture starts fresh
                // Released while the gesture's NET translation was still upward (resize): the
                // resized height is KEPT as-is (no snap-back, no dismiss check) — `dragOffset` is
                // guaranteed 0 here (the resize branch above always resets it), so there's nothing
                // to animate. It only reverts on the next presentation (fresh `@State`).
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }
}
