import SwiftUI
import LivebuyUI

// MARK: - GesturePauseIconView — family-1 center pause icon (RETIRED, rb-ios-gesture-clean-mode-rewrite)
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI PlayerShellView 手勢重寫：單擊依直播/VOD 分流切換靜音或播放/暫停，
//      長按切換乾淨模式" (RENAMED FROM "…提供長按暫停手勢 + 中央 pause icon").
// Design: `design/templates/minimal/sdk-components.jsx` `LBPGestureHint`「長按畫面 = 暫停 / 繼續」
//   (superseded copy — see `LiveOverlayChromeView.hintHold`).
//
// RETIRED (rb-ios-gesture-clean-mode-rewrite): `PlayerShellView` no longer composes this
// view — long-press no longer drives pause/resume (it now toggles `cleanMode`), so the
// transient `isHolding` @State it used to key off no longer means "hold-to-pause is in
// progress". The new central overlay is `PlaybackPausedOverlayView`, driven by the REAL
// `model.isPlaying` rather than a gesture transient, and is interactive (two buttons)
// rather than a static glyph.
//
// KEPT (not deleted): `GestureFeedbackSnapshotTests.testGesturePauseIcon` still
// constructs this type directly and owns an existing baseline PNG
// (`gesture-pause-icon.png`) — deleting the type would orphan that baseline (design.md
// §5: delete-vs-deprecate depends on whether apply-stage grep finds a live reference; it
// does, so this is marked `@available(*, deprecated)` rather than deleted — the one
// remaining call site's own deprecation warning is expected/harmless).
//
// PURE呈現: it reads only `theme` and paints a translucent dark circle + a pause glyph.
// It owns NO state. Renders correctly standalone (demo / snapshot).
//
// iOS-14-safe SwiftUI only: `ZStack` / `Circle` / `Image(systemName:)`. No Lazy* /
// ScrollView / AsyncImage / .foregroundStyle / .tint.

/// The centred hold-to-pause icon: a translucent dark circle with a white pause glyph.
/// RETIRED from production use (see file header) — kept only so its existing standalone
/// snapshot test / baseline keep compiling and passing.
@available(*, deprecated, message: "long-press no longer drives pause/resume; PlayerShellView composes PlaybackPausedOverlayView instead")
public struct GesturePauseIconView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    public init(theme: ReferenceUITheme) {
        self.theme = theme
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(Self.glass)
                .frame(width: 72, height: 72)
            Image(systemName: "pause.fill")
                .font(.system(size: 30 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
        }
    }

    /// Translucent dark circle surface (rgba(20,20,24,0.62)).
    static let glass = (Color(hex: "#141418") ?? .black).opacity(0.62)
}

#if DEBUG
struct GesturePauseIconView_Previews: PreviewProvider {
    static var previews: some View {
        GesturePauseIconView(theme: ReferenceUIThemePalette.minimal)
            .padding()
            .background(Color.gray)
            .previewLayout(.sizeThatFits)
    }
}
#endif
