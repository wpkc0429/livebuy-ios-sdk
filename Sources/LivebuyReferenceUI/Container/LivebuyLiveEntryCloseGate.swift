import Foundation

// MARK: - LivebuyLiveEntryCloseGate — collapsible-player-close → live-entry grace bridge
//                                      (rb-ios-live-entry-close-grace-period)
//
// WHY THIS EXISTS. 使用者回報：看完直播、把播放器縮小成懸浮小卡、點關閉鈕整個關掉之後，如果店裡
// 剛好有另一場直播正在進行，`LivebuyLiveEntry`（獨立的「現正直播」浮窗入口）幾乎立刻在同一個角落
// 跳出來，讓使用者感覺「好像沒有真的關掉、有點干擾」。根因：`CollapsibleLivebuyPlayer`（iOS 對應
// 的是 `LivebuyPlayerPresenter`）跟 `LivebuyLiveEntry` 是兩個完全獨立的元件——`LivebuyLiveEntry`
// 只在 host 判斷「沒有播放器在前景」（`sessionVideo == nil`）時才會掛載，所以「關閉播放器」跟「入口
// 卡冒出來」在時間上幾乎同時，視覺上就像同一張卡片沒真的關掉。
//
// `LivebuyLiveEntry` 本來就有一套「進場延遲」設定（`LBFloatingEntryTiming` / `LivebuyLiveEntryConfig
// .delay`，來自商家後台 `POST /sdk/config` 的 `floating_setting`），但那組設定的語意是「使用者一打開
// app、還沒看過任何影片時，首頁的入口卡要不要延遲出現」——跟這裡「剛關閉播放器」的觸發時機完全不
// 同，不能直接借用同一個值（已與使用者逐項確認過）。這座橋是一個獨立、跟商家設定完全無關、SDK
// 內建、固定 2 秒的「關閉後緩衝」，只在「緊接在播放器關閉之後」才生效——真正冷開 app（從未關閉過
// 任何播放器，`lastClosedAt == nil`）完全不受影響，照舊只吃 `floating_setting` 既有邏輯。
//
// SHAPE（風格參照 `Widget/LivebuyWidgetVisibility.swift` 的「小型 opt-in bridge singleton」寫法）：
// `LivebuyPlayerPresenter`（iOS 的 collapsible player）在使用者真正關閉整個 session 時
// （`closeSession()`——floating card 的關閉鈕 / 全螢幕的 fatal-moment dismiss；不含 minimize /
// tap-to-restore，見該方法的 doc）呼叫 `recordClosedNow()`；`LivebuyLiveEntry` 在決定「等多久才
// 出現」時讀出「距上次關閉過了多久」，跟商家設定的延遲取 `max`（見 `LivebuyLiveEntry
// .scheduleAppearance(eligible:)` 與 `lbLiveEntryActualAppearDelay(configuredDelay:closeGraceRemaining:)`）。
//
// 跟 `LivebuyWidgetVisibility` 的差異：那座橋是 PUBLIC——一個手捲導覽 / 裸 `LivebuyPlayer` 的 host
// 可能需要自己呼叫（見該檔案頭的 MANUAL PATH）。這座橋是 INTERNAL：兩端（`LivebuyPlayerPresenter`
// / `LivebuyLiveEntry`）都是本套件內建的 turnkey 容器，host 完全不需要、也看不到這座橋，故刻意不升
// public（不無謂擴大 API surface；若未來真的出現需要手捲橋接的 host，屆時再評估升級）。
//
// TESTABILITY（internal-testability）：真正要測的是下面三個純函式——`msSinceLastPlayerClose` /
// `liveEntryCloseGraceRemaining` / `lbLiveEntryActualAppearDelay`——三者皆吃明確傳入的時間值，不直
// 接呼叫 `Date()`，可確定性單測邊界案例（從未關閉 / 剛好 2 秒 / 短於 2 秒 / 超過 2 秒 /
// max() 組合）。`LivebuyLiveEntryCloseGate` 這個 class 本身只是持有 `Date?` 的薄薄一層 impure
// glue，寫入用真實 `Date()`，不強求完整覆蓋——跟本套件既有的 `collapsiblePhase` /
// `shouldReopenOnVideoChange` 等純函式測試慣例一致。
//
// MAIN-THREAD-ONLY contract（同 `LivebuyWidgetVisibility`）：`recordClosedNow()` 由 SwiftUI view
// body / closure 在主執行緒呼叫；讀取（`closeGraceRemaining`）同樣只在主執行緒的 view body 內發
// 生。無鎖。

/// 距離上次關閉播放器過了多久（秒）。`lastClosedAt` 為 `nil`（從未關閉過——即真正冷開 app）時回傳
/// `nil`；否則回傳 `now.timeIntervalSince(lastClosedAt)`。純函式：不直接呼叫 `Date()`，時間一律由
/// 呼叫端明確傳入，可確定性單測。
func msSinceLastPlayerClose(lastClosedAt: Date?, now: Date) -> TimeInterval? {
    guard let lastClosedAt = lastClosedAt else { return nil }
    return now.timeIntervalSince(lastClosedAt)
}

/// `LivebuyLiveEntry` 因「剛關閉播放器」還要再等多久才能出現（秒）。`msSinceClose == nil`（從未
/// 關閉過）或已經過了 `graceSeconds`（含剛好等於，邊界不算在緩衝期內）→ `0`（緩衝已耗盡 / 不適
/// 用）；否則回傳尚餘的秒數（`graceSeconds - msSinceClose`）。`graceSeconds` DEFAULT `2.0`——SDK
/// 內建固定值，與商家後台 `floating_setting` 完全無關，不開放設定（已與使用者確認：「固定寫死 2
/// 秒，不開放商家設定」）。純函式。
func liveEntryCloseGraceRemaining(
    msSinceClose: TimeInterval?, graceSeconds: TimeInterval = 2.0
) -> TimeInterval {
    guard let msSinceClose = msSinceClose, msSinceClose < graceSeconds else { return 0 }
    return graceSeconds - msSinceClose
}

/// `LivebuyLiveEntry` 實際要等多久才出現：既有商家設定延遲（`lbLiveEntryAppearDelay`）與這裡的
/// 「關閉後緩衝」（`liveEntryCloseGraceRemaining`）兩者取 **`max`**——不是相加、不是取代。冷開時
/// `closeGraceRemaining` 恆 `0`，`max` 退化回 `configuredDelay` 本身，對既有商家設定行為零副
/// 作用；剛關閉時若商家設定的延遲短於（或不存在）緩衝，緩衝把等待時間拉長到（至多）
/// `graceSeconds`，商家設定更長時則維持商家設定值不變。純函式（供單測直接打，不必真的 mount 容
/// 器——同 `lbLiveEntryAppearDelay` 系列的既有測試慣例；`scheduleAppearance` 本身的 wall-clock
/// 排程行為仍只能靠模擬器／真機目視驗證，見 `LiveEntryPositionTimingTests.swift` 檔頭的既有誠實
/// 覆蓋邊界說明）。
func lbLiveEntryActualAppearDelay(
    configuredDelay: TimeInterval, closeGraceRemaining: TimeInterval
) -> TimeInterval {
    max(configuredDelay, closeGraceRemaining)
}

/// Opt-in 內部橋：`LivebuyPlayerPresenter`（iOS 的 collapsible 播放器）在使用者真正關閉整個
/// session 時記錄「現在」；`LivebuyLiveEntry` 讀出「距上次關閉過了多久」，算出剩餘的關閉後緩
/// 衝。INTERNAL（不像 `LivebuyWidgetVisibility` 那樣 public）——兩端都是本套件內建的 turnkey 容
/// 器，host 不需要、也看不到這座橋。Main-thread-only（同 `LivebuyWidgetVisibility`），故無鎖。
final class LivebuyLiveEntryCloseGate {

    /// SDK 內建固定的關閉後緩衝秒數。跟商家後台 `floating_setting` 完全無關，不開放設定。
    static let graceSeconds: TimeInterval = 2.0

    /// The process-wide shared bridge.
    static let shared = LivebuyLiveEntryCloseGate()

    private init() {}

    /// 上次使用者真正關閉播放器 session 的時間；`nil` = 從未關閉過（真正冷開 app）。
    private(set) var lastClosedAt: Date?

    /// `LivebuyPlayerPresenter.closeSession()` 在使用者真正關閉整個 session 時呼叫（floating
    /// card 的關閉鈕 / 全螢幕的 fatal-moment dismiss；不含 minimize / tap-to-restore，見
    /// `closeSession()` 的 doc）。寫入真實 `Date()`——薄薄一層 impure glue，真正的邏輯在上面三
    /// 個純函式。
    func recordClosedNow() {
        lastClosedAt = Date()
    }

    /// 此刻（`now`，DEFAULT 真實 `Date()`）距上次關閉還要再等多久才能出現（秒）——組合上面兩個
    /// 純函式（`msSinceLastPlayerClose` + `liveEntryCloseGraceRemaining`）的 impure 便利
    /// wrapper，供 `LivebuyLiveEntry.scheduleAppearance` 直接呼叫。
    func closeGraceRemaining(now: Date = Date()) -> TimeInterval {
        liveEntryCloseGraceRemaining(
            msSinceClose: msSinceLastPlayerClose(lastClosedAt: lastClosedAt, now: now),
            graceSeconds: Self.graceSeconds)
    }

    /// Test-only reset（internal-testability）：清回「從未關閉過」，避免測試之間互相汙染這個
    /// process-wide 單例（同 `LivebuyWidgetVisibility.resetForTesting()` 的既有慣例）。
    func resetForTesting() {
        lastClosedAt = nil
    }
}
