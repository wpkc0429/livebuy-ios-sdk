import SwiftUI
import LivebuySDK

// MARK: - LiveNowPollController — lightweight "is another live in progress" poller
//
// Change: rb-ios-live-now-pill.
// Depends On: `dropin-live-entry-container`（reuses `Livebuy.fetchLatestLive` + the existing
//   `lbLiveEntryGate` purity — see `LivebuyLiveEntry.swift`）.
//
// `LivebuyPlayer` needs to know "is there currently another live in progress" so it can show
// `LiveNowPillView`. `LivebuyLiveEntryController` (in `LivebuyLiveEntry.swift`) already owns a
// PROVEN poll/gate lifecycle for exactly this signal — but `LivebuyLiveEntry` is a SEPARATE,
// independently-mountable drop-in surface (a floating corner entry card); `LivebuyPlayer` MUST
// NOT share its `LivebuyLiveEntryController` instance (that would couple two otherwise-decoupled
// drop-in surfaces the host can each opt into independently — headless / single-source-of-truth
// invariants).
//
// This controller is the DELIBERATELY LIGHTER counterpart: it owns ONLY the three things
// `LiveNowPillView` actually needs — poll interval, failure fast-retry, and the `liveStatus == 1`
// gate (reusing the existing pure `lbLiveEntryGate(_:)`, not a re-implementation) — none of
// `LivebuyLiveEntryController`'s dismiss / drag-clamp / entrance-animation / live-end-notification
// machinery, which is specific to a user-dismissible floating card and has no equivalent concept
// for a pill embedded in the player chrome.
public final class LiveNowPollController: ObservableObject {

    /// The currently detected "another live in progress" video, or `nil`. Drives
    /// `PlayerShellView.hasLiveNow` (→ `LiveNowPillView`'s presence). Always `nil` when `shopId`
    /// is unset (`start()` never actually polls) or the backend currently has no
    /// `liveStatus == 1` live for this shop.
    @Published public private(set) var liveNow: LBVideoItem?

    private let shopId: String?
    private let pollInterval: TimeInterval
    /// Injected fetch side effect (internal-testability: ctor-injected, default
    /// `Livebuy.fetchLatestLive(id:)`) — a test substitutes a `Fake*` closure instead of hitting
    /// the network, mirroring `LivebuyLiveEntryController`'s identical seam.
    private let fetch: (String) async throws -> LBVideoItem?

    private var pollTask: Task<Void, Never>?

    public init(shopId: String?,
                pollInterval: TimeInterval = 30,
                fetch: @escaping (String) async throws -> LBVideoItem? = { try await Livebuy.fetchLatestLive(id: $0) }) {
        self.shopId = shopId
        self.pollInterval = pollInterval
        self.fetch = fetch
    }

    // MARK: - 輪詢生命週期

    /// 起輪詢（冪等：已在跑就跳過）。`shopId == nil`（host 沒有 opt-in `LivebuyPlayerConfig.shopId`）
    /// → 永遠不會真的打任何 API、`liveNow` 永遠停在 `nil`、`LBLiveNowPill` 永遠不出現——headless
    /// 慣例：host 沒有明確 opt-in 就零額外副作用。
    public func start() {
        guard let shopId = shopId, pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.pollLoop(shopId: shopId) }
    }

    /// 停輪詢（容器 dismantle 時呼叫，對稱 `start()`）。
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// `do/catch`（非 `try?`）比照 `LivebuyLiveEntryController.pollLoop`：區分「目前沒有直播」
    /// （`nil` → 清空鈕）與「請求失敗 / 尚未 configure」（throw → **保留**上一輪的值、3s 快重試）——
    /// 一次暫時的網路抖動不該讓鈕閃爍消失又出現。
    private func pollLoop(shopId: String) async {
        while !Task.isCancelled {
            do {
                let video = try await fetch(shopId)
                let gated = lbLiveEntryGate(video)
                await MainActor.run { self.apply(gated) }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                try? await Task.sleep(nanoseconds: 3_000_000_000)   // 3s 快重試（pre-configure / 網路）
            }
        }
    }

    /// Test-only / internal seam：直接套用一筆**已 gate** 的結果（比照
    /// `LivebuyLiveEntryController.apply`），讓單測能驅動狀態轉移而不需要真的跑輪詢 `Task` 迴圈 /
    /// 等待 `Task.sleep`。
    func apply(_ gated: LBVideoItem?) {
        liveNow = gated
    }

    deinit {
        pollTask?.cancel()
    }
}
