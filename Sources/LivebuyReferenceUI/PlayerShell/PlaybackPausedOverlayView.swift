import SwiftUI
import LivebuyUI

// MARK: - PlaybackPausedOverlayView — family-1 center paused overlay (interactive)
//
// ⚠️ RETIRED (`rb-ios-gesture-clean-mode-v2`, design R29): `PlayerShellView` no longer
// composes this view — the R29 gesture model removes the central paused overlay entirely.
// VOD / already-ended-live-replay play/pause is now driven by the existing
// `PlaybackProgressBarView`'s expanded-state play/pause button instead (that button already
// exists and is reachable whenever `isExpanded == true`, which `cleanMode` already feeds
// into). This file is kept (struct definition + `LBAccessibilityID` ids untouched) rather
// than deleted — mirroring this exact module's own precedent for the PREVIOUS retired
// central overlay, `GesturePauseIconView.swift` (see its header comment) — so a future
// change that wants to resurrect a central overlay has a working starting point, and so
// this diff does not also have to hunt down every remaining reference.
//
// Everything below this point describes the ORIGINAL (`rb-ios-gesture-clean-mode-rewrite`,
// design R23) behavior, kept verbatim as a historical record.
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI PlayerShellView 手勢重寫：單擊依直播/VOD 分流切換靜音或播放/暫停，
//      長按切換乾淨模式" — 「中央暫停覆蓋層改為綁真實播放狀態的互動雙按鈕」.
// Design: `design/templates/minimal/screens.jsx:342-372` (the `isMain && paused` block) —
//   two stacked glass buttons (mute-toggle 44px, resume 64px), `rgba(0,0,0,0.45)` fill.
// Change: rb-ios-gesture-clean-mode-rewrite.
//
// TAKES OVER from the retired `GesturePauseIconView` (a single static, non-interactive
// glyph driven by the TRANSIENT gesture flag `isHolding` — shown only while the finger
// was down, gone on release). This overlay is driven by the REAL playback state
// (`PlayerShellView` composes it ⟺ `isMain && !model.isPlaying`) and stays up — and
// stays INTERACTIVE — for as long as the engine is actually paused, however that
// pause was triggered (a VOD/replay tap, or an SDK-internal lifecycle `pause()`).
//
// PURE呈現: reads only its passed-in values, owns no state, and never reaches back
// into `PlayerShellModel` / `DefaultPlayerTemplate` (one-way data flow, D-1/D-4). Both
// buttons forward to host-wired closures the shell already owns:
//   - 靜音切換 (44px) → `onToggleMute` (the SAME closure the video-area tap uses on a
//     LIVE stream — this overlay only ever shows for a NON-live stream, but the mute
//     affordance is still meaningful there, per the design's paused overlay).
//   - 播放恢復 (64px) → `onResume` (the shell wires this to `model.togglePlayPause()`;
//     since the overlay only shows while genuinely paused, "toggle" here always means
//     "resume").
//
// iOS-14-safe SwiftUI only: `VStack` / `Circle` / `Image(systemName:)` / `Button`. No
// Lazy* / ScrollView / AsyncImage / .foregroundStyle / .tint.

/// The centred, interactive "paused" overlay: a mute-toggle button (44px) stacked
/// above a play/resume button (64px), both on translucent dark-glass circles.
public struct PlaybackPausedOverlayView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The CURRENT mute state (`PlayerShellModel.muted`) — selects the glyph
    /// (`speaker.slash.fill` muted / `speaker.wave.2.fill` unmuted), matching
    /// `GestureMuteToastView`'s icon convention.
    public let muted: Bool

    /// Tap the mute-toggle button → host-wired mute forwarder (the SAME closure the
    /// video-area tap-to-mute gesture uses). `nil` → the button renders but is inert
    /// (demo / snapshot).
    public let onToggleMute: (() -> Void)?

    /// Tap the resume button → resume playback. `PlayerShellView` wires this to
    /// `model.togglePlayPause()` (meaningful only as "resume" here, since the overlay
    /// is shown ⟺ the engine is actually paused). `nil` → inert (demo / snapshot).
    public let onResume: (() -> Void)?

    public init(theme: ReferenceUITheme,
                muted: Bool,
                onToggleMute: (() -> Void)? = nil,
                onResume: (() -> Void)? = nil) {
        self.theme = theme
        self.muted = muted
        self.onToggleMute = onToggleMute
        self.onResume = onResume
    }

    public var body: some View {
        VStack(spacing: 14) {
            Button(action: { onToggleMute?() }) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: Self.muteButtonSize, height: Self.muteButtonSize)
                    .background(Circle().fill(Self.glass))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.pausedOverlayMuteButton)

            Button(action: { onResume?() }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: Self.resumeButtonSize, height: Self.resumeButtonSize)
                    .background(Circle().fill(Self.glass))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.pausedOverlayResumeButton)
        }
        .accessibilityElement(children: .contain)
    }

    /// Mute-toggle button diameter (design 44px).
    static let muteButtonSize: CGFloat = 44
    /// Resume button diameter (design 64px).
    static let resumeButtonSize: CGFloat = 64
    /// Translucent dark-glass circle fill (design `rgba(0,0,0,0.45)`).
    static let glass = Color.black.opacity(0.45)
}

#if DEBUG
struct PlaybackPausedOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            PlaybackPausedOverlayView(theme: ReferenceUIThemePalette.minimal, muted: true)
        }
        .frame(width: 200, height: 200)
        .previewLayout(.sizeThatFits)
    }
}
#endif
