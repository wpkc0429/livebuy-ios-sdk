import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - ProductRowView — reusable product-card component (row / grid two states)
//
// Spec: `reference-ui-rendering/spec.md` §"LivebuyReferenceUI 商品卡元件（row / grid 兩態）供
//        商品列表與商品明細更多商品推薦格共用"
// Design: rb-ios-product-detail-recommendations tasks.md §1 +
//          `design/templates/minimal/sdk-components.jsx` `LBPProductRow` (design R21,
//          `design/contract/claude-design-sync.md` §R21).
//
// Extracted from `ProductListView`'s former private `productRow(_:index:)` function
// (rb-ios-product-detail-recommendations §1). `ProductListView` now constructs this
// view for its EXISTING `.row` call site — behavior / pixels UNCHANGED (see the
// `.row` DELIBERATE DEVIATION note below). The new `.grid` layout is used ONLY by
// the「更多商品」推薦格 (`ProductDetailSheetView`'s recommendations section).
//
// iOS-14-safe SwiftUI only, mirrors `ProductListView`'s existing constraints.

/// Which card geometry this row renders (design R21).
public enum ProductRowLayout: Equatable {
    /// The existing horizontal list row (thumbnail · name/price · action-icon group) —
    /// `ProductListView`'s product list drawer.
    case row
    /// The new vertical card (thumbnail on top, info below) — used ONLY by the
    /// 「更多商品」推薦格 (2×2, always `hideSub: true`).
    case grid
}

/// A single product card, in either the existing `.row` layout or the new `.grid`
/// layout (rb-ios-product-detail-recommendations §1). All action closures are
/// NO-ARG — the caller captures the specific `product` it is rendering when
/// constructing this view per iteration (mirrors how `ProductSheetsOverlayView`
/// already captures per-item closures when wiring `ProductListView`).
public struct ProductRowView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The product this card renders. For `.grid` (推薦格) call sites this MAY be a
    /// presentation-only conversion of `LBProductRecommendation`
    /// (`LBProductRecommendation.asDisplayProduct`) — see that extension's doc for why
    /// it is safe to use for RENDERING while the tap closures resolve the real
    /// `LBProduct` independently.
    public let product: LBProduct

    /// Row index — used only for the `row` layout's per-item accessibility identifiers
    /// (unused by `.grid`, which has its own identifier scheme).
    public let index: Int

    /// `false` (snapshot / demo) → thumbnail draws the deterministic placeholder only.
    /// `true` (host runtime) → loads `product.photos.first` / `product.pic` over the
    /// placeholder via `RemoteStillImageView` (rb-ios-product-real-images).
    public let live: Bool

    /// `.row` (default) or `.grid` (design R21).
    public let layout: ProductRowLayout

    /// Hides the secondary text line under the product name (struck-through original
    /// price / 已售完 sub-line). Default `false` (existing `.row` behavior unchanged).
    /// The「更多商品」推薦格 call site MUST pass `true` (`LBProductRecommendation` carries
    /// no original-price / narrating data to show there).
    public let hideSub: Bool

    /// `.row`-only: playback-mode overlay decision inputs (rb-ios-product-row-status-overlay).
    /// Ignored entirely by `.grid` (cross-video recommendation cards have no live-narrating
    /// concept). Defaults reproduce `ProductListView`'s existing VOD fallback.
    public let mode: ProductRowMode
    public let isNarrating: Bool
    public let playbackPosition: Int

    /// Host-wired 卡片本體 / 名稱 tap → open detail (`ProductListView.onOpenProduct` /
    /// the recommendation grid's card-body tap). nil → no-op (demo / snapshot).
    private let onOpenProduct: (() -> Void)?

    /// Host-wired 加購鈕 tap (`.row`: in-stock cart glyph / `.grid`: the independent accent
    /// cart circle). nil → no-op.
    private let onQuickAdd: (() -> Void)?

    /// `.row`-only: 售完列補貨鈴鐺鈕 tap. nil → no-op. `.grid` never shows this affordance
    /// (sold-out recommendation cards simply hide the cart circle, design R21).
    private let onNotifyRestock: (() -> Void)?

    /// `.row`-only: 縮圖點擊 → seek to intro (issue 5). Also the FALLBACK for `onPlayClick`
    /// when the latter is nil (design R21 "未傳退回 onSeek").
    private let onSeekToIntro: (() -> Void)?

    /// `.row`-only: 列分享鈕 tap (issue 6). `.grid` never shows a share icon.
    private let onShareProduct: (() -> Void)?

    /// Independent 播放/看講解 tap handler (rb-ios-product-detail-recommendations §1.3).
    /// `.row`: nil falls back to `onSeekToIntro` (design R21 "未傳退回 onSeek") — so
    /// `ProductListView`'s existing call site (never passes this) is behavior-unchanged.
    /// `.grid`: this ALSO gates whether the play button is shown at all — the caller
    /// (the recommendations renderer) MUST only pass a non-nil closure when the
    /// underlying `LBProductRecommendation.videoId` is non-nil (task 4.1: a nil
    /// `videoId` MUST hide/disable the play affordance, not present a dead button).
    private let onPlayClick: (() -> Void)?

    /// Continuous-animation throttling gate for the `.grid` play button's breathing
    /// pulse (mirrors `WinEntryView` — ios-power-profile-animation-throttle-reference-ui).
    /// `ImageRenderer` never fires `.onAppear`, so the resting frame is captured
    /// regardless — snapshot goldens stay deterministic.
    @Environment(\.continuousAnimationGate) private var motionGate

    /// Local breathing-pulse animation state for the `.grid` play button (mirrors
    /// `WinEntryView.pulsing`). Never driven by a core call — purely presentational.
    @State private var breathing = false

    public init(
        theme: ReferenceUITheme,
        product: LBProduct,
        index: Int = 0,
        live: Bool = false,
        layout: ProductRowLayout = .row,
        hideSub: Bool = false,
        mode: ProductRowMode = .vod,
        isNarrating: Bool = false,
        playbackPosition: Int = 0,
        onOpenProduct: (() -> Void)? = nil,
        onQuickAdd: (() -> Void)? = nil,
        onNotifyRestock: (() -> Void)? = nil,
        onSeekToIntro: (() -> Void)? = nil,
        onShareProduct: (() -> Void)? = nil,
        onPlayClick: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.product = product
        self.index = index
        self.live = live
        self.layout = layout
        self.hideSub = hideSub
        self.mode = mode
        self.isNarrating = isNarrating
        self.playbackPosition = playbackPosition
        self.onOpenProduct = onOpenProduct
        self.onQuickAdd = onQuickAdd
        self.onNotifyRestock = onNotifyRestock
        self.onSeekToIntro = onSeekToIntro
        self.onShareProduct = onShareProduct
        self.onPlayClick = onPlayClick
    }

    // MARK: - Shared derived state

    /// 狀態標籤吃後端結論欄 `label`（rb-ios-goods-label-unified ③，單一優先序）；`label` 空
    /// （舊後端 / demo / `.grid`'s `LBProductRecommendation` conversion, which never sets a
    /// label）falls back to the raw fields in the SAME priority order — so this reduces to
    /// plain `product.soldOut == 1` for `.grid` while reproducing `.row`'s exact prior
    /// behavior (label-priority) verbatim.
    private var soldOut: Bool { ProductStatusBadge.resolve(product) == .soldOut }

    /// `.row`-only overlay decision (rb-ios-product-row-status-overlay /
    /// rb-ios-live-hide-product-share). Unused by `.grid`.
    private var overlay: (showPlay: Bool, showIntroducing: Bool, showShare: Bool) {
        ProductRowOverlay.decide(
            mode: mode,
            isNarrating: isNarrating,
            beginTime: product.beginTime,
            endTime: product.endTime,
            position: playbackPosition)
    }

    /// 優先序 sold_out > narrating：售罄時壓過「介紹中」橫幅（rb-ios-goods-label-unified ③,
    /// verbatim from the pre-extraction `productRow(_:index:)`).
    private var isIntroducing: Bool { overlay.showIntroducing && !soldOut }

    public var body: some View {
        switch layout {
        case .row:
            rowBody
        case .grid:
            gridBody
        }
    }

    // MARK: - `.row` layout — BYTE-IDENTICAL to the pre-extraction `productRow(_:index:)`
    //
    // DELIBERATE DEVIATION (baseline protection — see the spec Requirement's note): design
    // R21 changes the `row` play-hint visual globally (black-circle icon → bottom「看講解」
    // text pill), but `ProductListView`'s 5 existing snapshot baselines lock the CURRENT
    // black-circle pixels and MUST NOT be regenerated without explicit user confirmation
    // (CLAUDE.local.md「不要動的地方」). So `.row` intentionally KEEPS the existing visual
    // here; only the ACTION wiring gains the `onPlayClick ?? onSeekToIntro` fallback
    // (task 1.3), which is a behavior-only change invisible to snapshot pixels for the
    // existing call site (`onPlayClick` defaults nil there).

    private var rowBody: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgSunken)
                if live, let url = Self.photoURL(product) {
                    RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                }
                if overlay.showPlay {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.5))
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 26, height: 26)
                }
                if isIntroducing {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            EqualizerGlyph(size: 9, color: .white)
                            Text(Self.introducingLabel)
                                .font(.system(size: 10 * theme.fontScale, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(theme.accent)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            // design R21 task 1.3: `onPlayClick` non-nil overrides the existing seek — nil
            // (ProductListView's existing call site) falls back to `onSeekToIntro` exactly
            // as before.
            .onTapGesture { (onPlayClick ?? onSeekToIntro)?() }
            .accessibilityIdentifier(LBAccessibilityID.productRowThumb(index))

            Button(action: { onOpenProduct?() }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                        .foregroundColor(theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !hideSub {
                        if soldOut {
                            Text(Self.soldOutLabel)
                                .font(.system(size: 12 * theme.fontScale))
                                .foregroundColor(Self.soldOutColor)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if !product.originalPriceShow.isEmpty,
                                   product.originalPriceShow != product.priceShow {
                                    Text(product.originalPriceShow)
                                        .font(.system(size: 12 * theme.fontScale))
                                        .foregroundColor(Self.textDim)
                                        .strikethrough(true, color: Self.textDim)
                                }
                                Text(product.priceShow)
                                    .font(.system(size: 14 * theme.fontScale, weight: .heavy))
                                    .foregroundColor(Self.saleColor)
                                switch ProductStatusBadge.fromLabel(product.label) {
                                case .outSoon: statusPill(Self.outSoonLabel, Self.outSoonColor)
                                case .hot:     statusPill(Self.hotLabel, theme.accent)
                                default:       EmptyView()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.productRowDetail(index))

            HStack(spacing: 8) {
                rowOutlineIcon("doc.text", action: onOpenProduct)
                if overlay.showShare {
                    rowOutlineGlyph(action: onShareProduct) {
                        ShareGlyph(size: 16, color: theme.accent)
                    }
                    .accessibilityIdentifier(LBAccessibilityID.productRowShare(index))
                }
                rowCartButton
                    .accessibilityIdentifier(LBAccessibilityID.productRowCart(index))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Self.stroke)
                    .frame(height: 1)
            }
        )
    }

    private func rowOutlineIcon(_ systemName: String, action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle().stroke(theme.accent, lineWidth: 1)
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(theme.accent)
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func rowOutlineGlyph<Glyph: View>(action: (() -> Void)?, @ViewBuilder glyph: () -> Glyph) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle().stroke(theme.accent, lineWidth: 1)
                glyph()
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// `.row`'s existing cart/bell circle (rb-ios-product-detail-recommendations §1: this
    /// element and its behavior are UNTOUCHED by this change — regression-locked by
    /// `ProductRowViewRowRegressionTests`).
    private var rowCartButton: some View {
        Button(action: {
            if soldOut {
                onNotifyRestock?()
            } else {
                onQuickAdd?()
            }
        }) {
            ZStack {
                Circle().fill(theme.accent)
                Image(systemName: soldOut ? "bell" : "cart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func statusPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10 * theme.fontScale, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    // MARK: - `.grid` layout — NEW (design R21, no existing baseline — free to design)
    //
    // Vertical card: square thumbnail (top-trailing breathing accent play circle, shown
    // only when `onPlayClick` is provided — task 4.1's videoId-nil gate lives at the
    // CALLER, which simply omits `onPlayClick` in that case) + name + price row with an
    // independent accent cart circle (hidden when sold out, design R21 "p.sold 時不顯示").
    // `hideSub` is expected `true` at the recommendations call site (no secondary line to
    // show there) but the row honours it either way, mirroring `.row`.

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgSunken)
                if live, let url = Self.photoURL(product) {
                    RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                }
                if onPlayClick != nil {
                    gridPlayButton
                        .padding(6)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(product.name)
                .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !hideSub && !soldOut && !product.originalPriceShow.isEmpty
                && product.originalPriceShow != product.priceShow {
                Text(product.originalPriceShow)
                    .font(.system(size: 11 * theme.fontScale))
                    .foregroundColor(Self.textDim)
                    .strikethrough(true, color: Self.textDim)
            }

            HStack(alignment: .center, spacing: 6) {
                if soldOut {
                    Text(Self.soldOutLabel)
                        .font(.system(size: 13 * theme.fontScale, weight: .bold))
                        .foregroundColor(Self.soldOutColor)
                } else {
                    Text(product.priceShow)
                        .font(.system(size: 14 * theme.fontScale, weight: .heavy))
                        .foregroundColor(Self.saleColor)
                }
                Spacer(minLength: 0)
                // Independent accent cart circle — design R21 "p.sold 時不顯示" (simply
                // hidden, not converted to a bell like `.row`'s rowCartButton).
                if !soldOut {
                    gridCartButton
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Self.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpenProduct?() }
        .accessibilityIdentifier(LBAccessibilityID.productRecommendationCard(index))
    }

    /// Top-right accent play circle with a breathing pulse (design R21 "呼吸閃爍").
    /// Gated by `onPlayClick != nil` at the call site (task 4.1). Mirrors
    /// `WinEntryView`'s `pulsing` driver + `continuousAnimationGate` throttle.
    private var gridPlayButton: some View {
        Button(action: { onPlayClick?() }) {
            ZStack {
                Circle().fill(theme.accent)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 24, height: 24)
            .opacity(breathing ? Self.breathOpacityMin : Self.breathOpacityMax)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear { startBreathing() }
        .onChange(of: motionGate) { _ in startBreathing() }
        .onDisappear { breathing = false }
        .accessibilityIdentifier(LBAccessibilityID.productRecommendationPlay(index))
    }

    /// Independent accent cart circle (design R21 grid `onCart`).
    private var gridCartButton: some View {
        Button(action: { onQuickAdd?() }) {
            ZStack {
                Circle().fill(theme.accent)
                Image(systemName: "cart")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.productRecommendationCart(index))
    }

    /// (Re)start the breathing pulse — mirrors `WinEntryView.startPulse()`. Skips the
    /// `repeatForever` driver under thermal pressure / Reduce Motion (leaves the button at
    /// its resting opacity); `ImageRenderer` never fires `.onAppear`, so snapshot goldens
    /// always capture the resting frame regardless.
    private func startBreathing() {
        breathing = false
        guard motionGate.allowsAnimation(visible: true) else { return }
        withAnimation(.easeInOut(duration: Self.breathDuration).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    // MARK: - Decorative design tokens (literal minimal hex — duplicated verbatim from
    // `ProductListView` / `ProductDetailSheetView`'s own token sets, the established
    // pattern in this module rather than a shared cross-file constant).

    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)
    static let saleColor = Color(hex: "#E0334B") ?? Color.red
    static let soldOutColor = Color(hex: "#9A96A3") ?? Color.gray
    static let outSoonColor = Color(hex: "#F5A623") ?? Color.orange

    static let soldOutLabel = "已售完"
    static let introducingLabel = "介紹中"
    static let outSoonLabel = "即將售完"
    static let hotLabel = "熱賣中"

    static let breathDuration: Double = 0.9
    static let breathOpacityMin: Double = 0.55
    static let breathOpacityMax: Double = 1.0

    /// First product photo (falling back to `pic`) as a non-empty URL, or nil.
    static func photoURL(_ product: LBProduct) -> URL? {
        let raw = product.photos.first ?? product.pic
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        return URL(string: s)
    }
}

// MARK: - LBProductRecommendation → LBProduct (PRESENTATION-ONLY conversion)
//
// `LBProductDetailState.recommendations` (`[LBProductRecommendation]`, from
// `expose-other-goods-recommendations-template`) is a DELIBERATELY minimal shape
// (`productId` / `name` / `priceShow` / `pic` / `videoId?` / `soldOut`) — it carries
// no `specifications` / `specOptions` / `originalPriceShow` / `stock` (design.md D2 of
// that template change). `ProductRowView` renders `LBProduct`, so this extension
// (added HERE in the reference-ui layer, mirroring the established pattern —
// `LBProductDetailState: Identifiable` is added the same way in
// `ProductSheetsOverlayView.swift`) builds a PRESENTATION-ONLY `LBProduct` carrying
// just enough to paint the `.grid` card correctly.
//
// ⚠️ This conversion MUST NOT be used as the payload for `onProductTap` / the nested
// detail's data — that would silently degrade the nested detail (no real
// specifications/stock). The container resolves the REAL `LBProduct` for a tapped
// recommendation from core `LivebuyPlayerViewController.channel?.otherGoods` (matched
// by `productId`) instead — see the "商品明細新增『商品介紹』文字區與『更多商品』推薦格"
// spec Requirement. This conversion exists ONLY to feed `ProductRowView`'s pixels.
extension LBProductRecommendation {
    var asDisplayProduct: LBProduct {
        LBProduct(
            id: productId, goodsNo: "", goodsGpn: "", name: name,
            price: 0, priceShow: priceShow, originalPrice: nil, originalPriceShow: "",
            stock: soldOut == 1 ? 0 : 1, pic: pic, photos: pic.isEmpty ? [] : [pic],
            brief: "", soldOut: soldOut, isHot: 0, isOutSoon: 0, narrateStatus: 0,
            isAwait: 0, isAwaitNotice: 0, beginTime: nil, endTime: nil, diversionUrl: "",
            specifications: [], specOptions: [], videoId: videoId)
    }
}
