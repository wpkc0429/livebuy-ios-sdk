import Foundation

// MARK: - LivebuyLiveEntryDismissMemory — dismiss-survives-remount 記憶
//                                          (rb-ios-live-entry-dismiss-survives-remount)
//
// WHY THIS EXISTS. `LivebuyLiveEntryConfig.onClose` 的既有 doc comment 早就明確承諾：「關閉鈕的
// 預設行為＝隱藏到『下一場』（換新 `video.id` 才重新出現）」。但這個承諾一直沒有真的兌現：
// `dismissed` 是存在 `LivebuyLiveEntryController`（`@StateObject`）**實例**上的狀態，而 host 只在
// 「沒有播放器在前景」時才會建立 `LivebuyLiveEntry`——每次開播放器、關播放器，`LivebuyLiveEntry`
// 就會整個從 SwiftUI tree 卸載再重新掛載一次，`LivebuyLiveEntryController` 隨之重新建構，
// `dismissed` 也跟著歸零。使用者對同一場直播明確按過關閉鈕，只要中途開過一次播放器再關掉，回到
// 沒有播放器在前景的畫面時，同一場直播的入口卡又會浮出來——「隱藏到下一場」在這條路徑上從未真的
// 成立過。
//
// 本檔補上這個記憶：讓「使用者明確按過關閉鈕」這個選擇，撐過容器重新掛載這一關。
//
// SHAPE（風格參照 `LivebuyLiveEntryCloseGate.swift` 的「小型 opt-in bridge singleton」寫法）：
// producer 與 consumer 都是 `LivebuyLiveEntry`（`LivebuyLiveEntryController.dismiss()` 寫、
// `LivebuyLiveEntryController.apply()` 讀）——是**同一元件跨實例**的自我記憶，不是像
// `LivebuyLiveEntryCloseGate` 那樣的「`LivebuyPlayerPresenter` 寫、`LivebuyLiveEntry` 讀」兩個元件
// 互通橋接。概念不同，故刻意開新檔案、新型別，不合併進 `LivebuyLiveEntryCloseGate`——維持「一座橋
// 一組明確的 producer/consumer」的既有分工。
//
// TESTABILITY（internal-testability）：真正要測的是純函式 `lbLiveEntryInitialDismissedForId`——吃
// 明確傳入的 `newId` / `lastDismissedId`，不直接讀共享狀態本身，可確定性單測邊界案例（nil / 相等 /
// 不同）。`LivebuyLiveEntryDismissMemory` 這個 class 本身只是持有 `String?` 的薄薄一層 impure
// glue，不強求完整覆蓋——跟 `LivebuyLiveEntryCloseGate` 的既有測試慣例一致。
//
// MAIN-THREAD-ONLY contract（同 `LivebuyLiveEntryCloseGate`）：`recordDismissed(liveId:)` 由
// `LivebuyLiveEntryController.dismiss()` 在主執行緒呼叫（`dismiss()` 本身即 `@Published` 寫入端，
// 已隱含主執行緒 contract）；讀取（`lastDismissedId`）同樣只在主執行緒的 `apply(_:)` 內發生。無鎖。
//
// 記憶只存在記憶體，process-wide，SDK 不寫入 `UserDefaults` 或任何持久化儲存——app process 重啟即
// 自然歸零，不視為 regression（已與使用者確認：「這個記憶只存在記憶體裡，app 重開自然歸零」）。

/// 換場時（或容器重新掛載後第一次套用某場直播）決定 `dismissed` 該以什麼初值起算：`newId` 非
/// `nil` 且等於 `lastDismissedId`（使用者上次明確關閉的那一場）→ `true`（維持隱藏）；否則
/// （包含 `newId == nil` 或兩者不同）→ `false`（正常可見）。純函式：不直接讀
/// `LivebuyLiveEntryDismissMemory` 本身，方便單測直接打。
///
/// 與既有 `lbLiveEntryShouldResetDismiss(currentId:newId:)` 是兩個獨立問題：那個純函式回答
/// 「id 變了、該不該重新求值 `dismissed`」；這個純函式回答「重新求值時該給什麼初值」——不修改、也
/// 不呼叫既有純函式。
func lbLiveEntryInitialDismissedForId(newId: String?, lastDismissedId: String?) -> Bool {
    guard let newId = newId else { return false }
    return newId == lastDismissedId
}

/// `LivebuyLiveEntry` 自己跨實例記住「使用者最後一次明確關閉的直播場次 id」。INTERNAL（不像
/// `LivebuyWidgetVisibility` 那樣 public）——producer 與 consumer 都是本套件內建的
/// `LivebuyLiveEntryController`，host 不需要、也看不到這個型別。Main-thread-only（同
/// `LivebuyLiveEntryCloseGate`），故無鎖。
final class LivebuyLiveEntryDismissMemory {

    /// The process-wide shared memory.
    static let shared = LivebuyLiveEntryDismissMemory()

    private init() {}

    /// 使用者最後一次明確按關閉鈕的直播場次 id；`nil` = 從未關閉過（或已被 `resetForTesting()`
    /// 清除）。單一值（非 `Set`）——容器同一時間點最多只 `live` 一場直播，`apply()` 只需要知道
    /// 「這一場」是不是「上一次關閉的那一場」，不需要記住歷史上所有被關閉過的場次（design.md D4）。
    private(set) var lastDismissedId: String?

    /// `LivebuyLiveEntryController.dismiss()` 在使用者明確按浮窗關閉鈕時呼叫（**唯一**寫入端——
    /// 「點入口卡進去看直播」的 `onTap` 路徑完全不呼叫此方法）。覆蓋既有值（非累加）：新的關閉
    /// 動作取代舊的記錄。
    func recordDismissed(liveId: String) {
        lastDismissedId = liveId
    }

    /// Test-only reset（internal-testability）：清回「從未關閉過」，避免測試之間互相汙染這個
    /// process-wide 單例（同 `LivebuyLiveEntryCloseGate.resetForTesting()` 的既有慣例）。
    func resetForTesting() {
        lastDismissedId = nil
    }
}
