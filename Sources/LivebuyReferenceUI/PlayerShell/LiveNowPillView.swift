import SwiftUI

// MARK: - LiveNowPillView — 「現正直播」右緣半藥丸鈕 (LBLiveNowPill)
//
// Spec: `reference-ui-rendering/spec.md` "LivebuyReferenceUI 渲染現正直播中提示鈕
//   （LiveNowPillView）"
// Design: `design/contract/claude-design-sync.md` R28 / `design/contract/components.md`
//   `LBLiveNowPill` / `design/templates/minimal/sdk-components.jsx` `LBLiveNowPill` +
//   `screens.jsx` `LBPPlayerScreen` mount block.
// Change: rb-ios-live-now-pill.
//
// VOD 播放中或直播回放時，若「目前有其他直播正在進行」，畫面右緣垂直置中顯示這顆紅色 LIVE 藥丸
// 鈕——內容為 14px 脈動白色圓點 + "LIVE" 文字 + 右箭頭 icon；`border-radius: 999px 0 0 999px`
// 貼右緣半藥丸。點擊呼叫 `onTap`（換片語意留給呼叫端決定，`LivebuyPlayer` 預設 in-place 換片、host
// 可覆寫）。
//
// PURE RENDERING + tap closure：本 view 不自己打 API、不自己輪詢——「目前有沒有另一場直播」與換片
// 邏輯都在容器層（`LivebuyPlayer` + `LiveNowPollController`），比照 `PlaybackProgressBarView` 一樣
// 「純渲染 sub-view，容器決定要不要組出來」的既有慣例。是否組出這顆鈕的顯示閘門是
// `PlayerShellView.showsLiveNowPill(...)`（PURE 靜態函式，比照既有 `showsPlaybackProgressBar`）。
//
// PULSE 動畫比照既有 `ProductRowView.gridPlayButton` 的 `continuousAnimationGate` 節流慣例
// （`ios-power-profile-animation-throttle-reference-ui`）：裝置過熱 / 使用者開 Reduce Motion /
// 離畫面時跳過啟動 `repeatForever` 驅動，只留靜止畫面——`ImageRenderer` snapshot 永遠只捕捉
// 那張靜止畫面，不受節流影響。
//
// iOS-14-safe：`ZStack` / `HStack` / `Circle` / 自訂 `Shape`（`Path`）/ `Image(systemName:)` 皆
// iOS-13+。

/// 只圓「前緣（左側）」兩個角——比照既有 `TopRoundedRectangle` 的 iOS-14-safe 逐角 `Shape` 寫法，
/// 套用到相反的一組角（design `borderRadius: 999px 0 0 999px`：`radius >= height/2` 時退化成
/// 「右緣貼齊平邊、左緣半圓」的半藥丸）。
struct LeadingRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + r),
            control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 右緣「現正直播」半藥丸鈕（`LBLiveNowPill`）。自我完備（無 view-model 綁定）——唯一的「綁定值」
/// 是要不要存在，由呼叫端（`PlayerShellView.showsLiveNowPill`）決定；本 view 對可見性沒有意見。
public struct LiveNowPillView: View {

    /// 已解析的 reference-ui theme（第一個位置參數，恆定慣例）。這顆鈕是固定品牌紅（design：
    /// `#F03246`，**不**跟 `theme.accent` 走——比照既有 `CarouselCardView.liveRed` /
    /// `MinimizedWidgetView` LIVE 標籤「固定 design 色、獨立於商家 theme」的先例）；`theme` 只用來
    /// 取 `fontScale`。
    public let theme: ReferenceUITheme

    /// 點擊 → host-wired 換片意圖。nil → inert（demo / snapshot）。
    private let onTap: (() -> Void)?

    @Environment(\.continuousAnimationGate) private var motionGate
    @State private var pulsing = false

    public init(theme: ReferenceUITheme, onTap: (() -> Void)? = nil) {
        self.theme = theme
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: Self.contentSpacing) {
                pulseDot
                Text(Self.label)
                    .font(.system(size: Self.labelFontSize * theme.fontScale, weight: .heavy))
                    .foregroundColor(.white)
                    .kerning(0.2)
                Image(systemName: "chevron.right")
                    .font(.system(size: Self.chevronSize * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(EdgeInsets(top: Self.paddingTop, leading: Self.paddingLeading,
                                bottom: Self.paddingBottom, trailing: Self.paddingTrailing))
            .background(Self.pillRed)
            .clipShape(LeadingRoundedRectangle(radius: 999))
            .shadow(color: Self.shadowColor, radius: Self.shadowRadius,
                   x: Self.shadowOffsetX, y: Self.shadowOffsetY)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear { startPulsing() }
        .onChange(of: motionGate) { _ in startPulsing() }
        .onDisappear { pulsing = false }
        .accessibilityIdentifier(LBAccessibilityID.liveNowPill)
    }

    // MARK: - 脈動圓點（14×14 外圈 + 5×5 實心中心）

    private var pulseDot: some View {
        ZStack {
            // 脈動外圈（design `lbp-pulse-dot` keyframe：向外放大同時淡出）。
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: Self.pulseRingLineWidth)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .scaleEffect(pulsing ? Self.pulseMaxScale : 1)
                .opacity(pulsing ? 0 : 1)
            // 靜止白色描邊圈。
            Circle()
                .stroke(Color.white, lineWidth: Self.dotBorderWidth)
                .frame(width: Self.dotSize, height: Self.dotSize)
            // 實心白點。
            Circle()
                .fill(Color.white)
                .frame(width: Self.dotInnerSize, height: Self.dotInnerSize)
        }
        .frame(width: Self.dotSize, height: Self.dotSize)
    }

    /// （重新）啟動脈動。裝置過熱 / Reduce Motion 下跳過 `repeatForever` 驅動（停在靜止、不可見的
    /// 外圈幀）——比照 `ProductRowView.startBreathing()`；`ImageRenderer` 從不觸發 `.onAppear`，故
    /// snapshot baseline 永遠捕捉靜止幀，不受節流與否影響。
    private func startPulsing() {
        pulsing = false
        guard motionGate.allowsAnimation(visible: true) else { return }
        withAnimation(.easeOut(duration: Self.pulseDuration).repeatForever(autoreverses: false)) {
            pulsing = true
        }
    }

    // MARK: - Design tokens（逐字取自 `sdk-components.jsx` `LBLiveNowPill`）

    static let pillRed = Color(hex: "#F03246") ?? .red
    static let label = "LIVE"

    static let contentSpacing: CGFloat = 6
    static let labelFontSize: CGFloat = 16
    static let chevronSize: CGFloat = 13

    static let paddingTop: CGFloat = 9
    static let paddingLeading: CGFloat = 10
    static let paddingBottom: CGFloat = 9
    static let paddingTrailing: CGFloat = 12

    static let dotSize: CGFloat = 14
    static let dotInnerSize: CGFloat = 5
    static let dotBorderWidth: CGFloat = 1.6
    static let pulseRingLineWidth: CGFloat = 1.4
    static let pulseMaxScale: CGFloat = 1.6
    static let pulseDuration: TimeInterval = 1.6

    static let shadowColor = Color.black.opacity(0.28)
    static let shadowRadius: CGFloat = 14
    static let shadowOffsetX: CGFloat = -2
    static let shadowOffsetY: CGFloat = 4
}

#if DEBUG
struct LiveNowPillView_Previews: PreviewProvider {
    static var previews: some View {
        LiveNowPillView(theme: ReferenceUIThemePalette.minimal)
            .padding(40)
            .background(Color(white: 0.15))
            .previewLayout(.sizeThatFits)
    }
}
#endif
