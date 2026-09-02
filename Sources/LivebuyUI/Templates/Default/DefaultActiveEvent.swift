import LivebuySDK

// MARK: - DefaultActiveEvent — 目前進行中活動狀態（live-activity-entry-template）
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template 目前進行中活動狀態（`LBActivitySheet` 行為）"
//   § "Default Template 加入目前活動（轉發既有 joinEvent）"
//   § "Default Template 換片立即隱藏並還原快取活動狀態（video-switch bridge）"
// Design: design.md D1 (即時讀穿、不快取) / D2 (attach 時補一次通知) / D3
//         (join 純轉發既有 joinEvent，見下方「為什麼 joinCurrentActivity() 不在這裡」)
//         / D4（直接暴露 public `LBActiveEvent`，不建中介型別）.
// Design (video-switch bridge, activity-entry-video-switch-cache-and-hide-ios):
//         D1 (bounded switch-override layered on top of, not replacing, the
//         original D1 live-passthrough read) / D2 (override expiry rides
//         `handlePollReceived`, not `ACTIVE_EVENT_STARTED`) / D3 (instance-scoped
//         cache, non-nil-only, no LRU bound) / D4 (pure lookup/insert functions).
// Design (multi-activity pagination, activity-sheet-multi-activity-template-ios):
//         **REVERSES** `live-activity-entry-template`'s original "明確不做：不處理
//         『同時多場活動』（`currentActivity` 只取第一筆）" decision — see design.md
//         D1 there for why. D2 (switch-override window now shapes `activities`
//         consistently with `currentActivity`, not just the single value) / D3
//         (page index stored raw, clamped only on read via a pure static) / D4
//         (`setActivityPageIndex` ignores out-of-range input rather than clamping
//         it) / D5 (page index resets to 0 on switch-arrival, folded into
//         `applySwitchOverride`).
//
// Behaviour / view-model layer ONLY (no pixels). The host draws `LBActivitySheet`
// (`{title, prizeName, keyword}`，見 `design/templates/minimal/moments.jsx`)
// bound to `currentActivity` — and, since `activity-sheet-multi-activity-template-ios`,
// may additionally bind to `activities` / `currentActivityPageIndex` /
// `setActivityPageIndex(_:)` to render pagination across multiple simultaneous
// activities (pixel rendering / swipe-gesture recognition are a later
// reference-ui-layer change; this type only prepares the data). Its「立即參加」
// CTA calls `DefaultPlayerTemplate.joinCurrentActivity()`. core stays headless: it
// never maintains a "current activity" merged state or pagination state, and
// never renders an entry / sheet.

/// Abstraction over the core's read-only active-events snapshot accessor
/// (`LivebuyPlayerViewController.activeEvents()`) so this view-model is
/// unit-testable with a `Fake`/`Capturing` provider — no live SDK / network
/// needed (mirrors `AwardClaimRequesting`'s abstraction of the win-claim entry
/// point). `LivebuyPlayerViewController` already exposes this exact signature;
/// it conforms via a source-compatible extension below (no behaviour change).
public protocol ActiveEventProviding: AnyObject {
    func activeEvents() -> [LBActiveEvent]
}

extension LivebuyPlayerViewController: ActiveEventProviding {}

/// 目前進行中活動狀態（`LBActivitySheet` 的資料來源）. Structurally mirrors
/// `DefaultWinClaim` (protocol-abstracted core dependency, internal
/// `onMutation` fanned by the owning `DefaultPlayerTemplate` into its single
/// host-facing `onChange`) — but is DELIBERATELY asymmetric in one respect:
/// see `currentActivity`'s doc comment (design.md D1) for why this state is
/// live-pull rather than cached-and-cleared like `unclaimedWinners`.
///
/// **`joinCurrentActivity()` is intentionally NOT exposed on this type.**
/// The only way to reach the existing join forwarder is
/// `DefaultPlayerTemplate.joinEvent(eid:keyword:)`, which lives on the type
/// that already OWNS this instance (`DefaultPlayerTemplate.activeEvent`).
/// Giving `DefaultActiveEvent` a reference back to its owner just to gain
/// that one call would invert the ownership direction for no real benefit, so
/// the public「加入目前活動」entry point is instead a thin forwarder directly
/// on `DefaultPlayerTemplate` (reads `activeEvent.currentActivity`, calls the
/// existing `joinEvent(eid:keyword:)`) — see that method's doc comment and
/// `tasks.md` §1.9 for the full reasoning.
public final class DefaultActiveEvent {

    private weak var provider: ActiveEventProviding?

    /// Instance-scoped, per-videoId last-known-non-nil `currentActivity` snapshot —
    /// used ONLY to bridge the display gap at video-switch time (video-switch bridge
    /// design.md D3). Deliberately NOT a process-level singleton like
    /// `VideoFeedSnapshotCache`: this instance survives every in-place switch within
    /// one player session (`DefaultPlayerTemplate.handleVideoSwitch` is an ordinary
    /// instance method mutating this same instance), so a plain dictionary already
    /// satisfies "switch back to an already-visited video this session shows its
    /// cached activity immediately." No LRU bound — instance lifetime already bounds
    /// growth, and each entry is one small `LBActiveEvent` value (see design.md D3
    /// for the full sizing argument).
    private var snapshotsByVideoId: [String: LBActiveEvent] = [:]

    /// Video-switch display override (video-switch bridge design.md D1 — extends,
    /// does NOT replace, the original D1 below). The OUTER optional is "is an
    /// override in effect at all" (`nil` = no, pure live-passthrough per the
    /// original D1); the INNER optional is the override's own payload (`nil` = hide,
    /// `.some(event)` = show immediately). Set by `applySwitchOverride(videoId:)`,
    /// unconditionally cleared by `clearSwitchOverride()` at most one poll round
    /// later (design.md D2) — so this can NEVER outlive a single ~5s poll cycle,
    /// carrying none of the original D1's "cached forever" risk.
    private var switchOverride: LBActiveEvent??

    /// Raw, UNCLAMPED page index into `activities` (multi-activity pagination,
    /// `activity-sheet-multi-activity-template-ios` design.md D3) — only ever
    /// written by `setActivityPageIndex(_:)` and the switch-arrival reset in
    /// `applySwitchOverride(videoId:)` (design.md D5). Deliberately NOT clamped at
    /// write time: `activities`' length can change between writes (poll-driven, no
    /// single "list changed" event to hook), so clamping happens lazily on every
    /// READ instead (`currentActivityPageIndex`, `currentActivity`) via the pure
    /// `clampedPageIndex(_:count:)` — any read is safe regardless of when the last
    /// write happened relative to the list shrinking.
    private var rawActivityPageIndex: Int = 0

    public init(provider: ActiveEventProviding?) {
        self.provider = provider
    }

    /// Full snapshot of all currently in-progress activities (multi-activity
    /// pagination, `activity-sheet-multi-activity-template-ios` design.md D1 —
    /// **REVERSES** the original `live-activity-entry-template` decision to expose
    /// only `activeEvents().first`; see that design.md's D1 for the full
    /// reasoning). Backs `currentActivity` below and lets a host render pagination
    /// (page dots / swipe — reference-ui layer, not this type's concern).
    ///
    /// Live pull, same non-caching rule as `currentActivity` — see its doc comment.
    /// **Honors the same bounded video-switch bridge override as `currentActivity`**
    /// (design.md D2): while `switchOverride` is in effect, this returns EXACTLY
    /// what the override implies — `[]` while hiding, a single-element `[event]`
    /// while restoring a cached snapshot (the switch-bridge cache only ever
    /// remembers ONE event per videoId, so a restored window can never show more
    /// than that one activity — not a limitation introduced here, see
    /// `snapshotsByVideoId`'s doc comment). Outside that window, this is a pure
    /// `provider?.activeEvents() ?? []` passthrough.
    public var activities: [LBActiveEvent] {
        if let override = switchOverride {
            return override.map { [$0] } ?? []
        }
        return provider?.activeEvents() ?? []
    }

    /// Pure: clamp `raw` into `activities`' current bounds — `0` for an empty list,
    /// otherwise `[0, count - 1]`. Never negative, never `>= count`, never crashes.
    /// Extracted so this safety rule is directly unit-testable with plain integers
    /// (docs/unit-test-discipline.md), mirroring `resolveSwitchOverride` /
    /// `remembering`'s "pure decision" pattern above.
    static func clampedPageIndex(_ raw: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(raw, 0), count - 1)
    }

    /// Current page index into `activities` (multi-activity pagination design.md
    /// D3) — ALWAYS safe to read: computed fresh from `rawActivityPageIndex` via
    /// `clampedPageIndex` against `activities`' CURRENT length, so a list that
    /// shrank since the last write (poll landed, an activity ended, a video switch
    /// happened) can never make this dangle or crash. `0` when `activities` is
    /// empty.
    public var currentActivityPageIndex: Int {
        Self.clampedPageIndex(rawActivityPageIndex, count: activities.count)
    }

    /// Switch the current page (multi-activity pagination design.md D4). An
    /// out-of-range `index` (negative, or `>= activities.count`) is a **no-op** —
    /// deliberately IGNORED rather than clamped to the nearest valid page (a
    /// caller passing a stale/racy index should not silently land on an
    /// unintended page it never asked for); the read-side clamp in
    /// `currentActivityPageIndex` already guarantees safety independent of what
    /// gets written here. Also a no-op (no `onMutation`) when `index` already
    /// equals the current raw index — mirrors `clearSwitchOverride()`'s
    /// no-change-no-notify style.
    public func setActivityPageIndex(_ index: Int) {
        guard activities.indices.contains(index) else { return }
        guard index != rawActivityPageIndex else { return }
        rawActivityPageIndex = index
        onMutation?()
    }

    /// The in-progress activity a host should currently surface (design.md D1 in
    /// `activity-sheet-multi-activity-template-ios`) — the entry `activities`'
    /// current page points to (`nil` when `activities` is empty). **Signature
    /// unchanged** from the original `live-activity-entry-template` single-activity
    /// design: only the VALUE's derivation changed (was: always `.first`; now: the
    /// paged entry), so existing callers (`joinCurrentActivity()`, the switch-bridge
    /// cache's `rememberSnapshot`/`applySwitchOverride`) needed zero changes — with
    /// the default `currentActivityPageIndex == 0`, this is byte-for-byte
    /// equivalent to the old "always first" behavior.
    ///
    /// **Computed, NOT stored / cached — outside the bounded video-switch bridging
    /// window.** Every read re-derives from `activities` (itself a fresh
    /// `provider.activeEvents()` read, `nil`/empty-safe). This is deliberate: core
    /// has no "activity ended" push event (`ACTIVE_EVENT_STARTED` fires only when an
    /// activity BEGINS), so caching this into an ordinary stored property — set once
    /// on `ACTIVE_EVENT_STARTED` — would go stale FOREVER once the activity actually
    /// ends, because nothing would ever clear it. Reading straight through to core's
    /// own poll-refreshed snapshot means the value is always correct the moment
    /// `activeEvents()` itself drops the finished entry — no clearing logic needed
    /// here at all.
    ///
    /// **One narrow, bounded exception** (video-switch bridge, design.md D1/D2):
    /// immediately after `applySwitchOverride(videoId:)` runs (on an in-place video
    /// switch), `switchOverride` (via `activities`, see its doc comment) takes
    /// priority over the live read for AT MOST one poll round — `clearSwitchOverride()`
    /// unconditionally drops it on the very next `handlePollReceived` call, after
    /// which this resumes the exact live passthrough described above. This is a
    /// display placeholder bridging the switch-to-first-poll gap, not an
    /// independent cache with its own clearing logic to maintain — see
    /// `ui-template-foundation/spec.md` § "Default Template 換片立即隱藏並還原快取
    /// 活動狀態（video-switch bridge）" for the full contract.
    ///
    /// Known, accepted limitation (design.md D1): this alone does not make
    /// the HOST repaint the instant an activity ends — `onMutation` only
    /// fires on `ACTIVE_EVENT_STARTED` / template attach / page-switch (see
    /// `notifyActivityStarted()` / `notifyAttachCompleted()` /
    /// `setActivityPageIndex(_:)`) — so a finished activity's entry may stay
    /// visually rendered until the next host-triggered redraw for any other
    /// reason. Accepted trade-off, not an oversight — see design.md D1 for the
    /// full cost/benefit discussion.
    public var currentActivity: LBActiveEvent? {
        let list = activities
        let idx = Self.clampedPageIndex(rawActivityPageIndex, count: list.count)
        return list.indices.contains(idx) ? list[idx] : nil
    }

    /// Internal coalesced "active-event state mutated" hook. The owning
    /// `DefaultPlayerTemplate` wires this to fan a single host-facing
    /// `onChange` (main thread), mirroring `DefaultWinClaim.onMutation`. NOT
    /// public — the host observes via the template's `onChange`; it does NOT
    /// subscribe to this model directly.
    var onMutation: (() -> Void)?

    /// `ACTIVE_EVENT_STARTED` (fire-once notification) landed — tell the host
    /// there is new content to read via `currentActivity`. Deliberately does
    /// NOT store the event payload as a field: `currentActivity` already reads
    /// straight through to core's live snapshot, so persisting a second copy
    /// here would only create a "two copies can disagree" risk (design.md D1).
    func notifyActivityStarted() {
        onMutation?()
    }

    /// Template attach (`TemplateWiring.attachPlayer`) just completed — fire
    /// the SAME "state changed" notification once, to close the "user joined
    /// mid-activity, already missed the fire-once `ACTIVE_EVENT_STARTED`"
    /// blind spot (design.md D2 — this is the exact use case core's
    /// `activeEvents()` accessor was documented for). Does NOT change any
    /// state: `currentActivity` already reads through to the live core
    /// snapshot (D1); this call exists purely to poke the host into reading
    /// it at least once right after attach. A separate name from
    /// `notifyActivityStarted()` on purpose — same effect (`onMutation?()`),
    /// but callers should not have to read "activity started" at an attach
    /// call site where no such event actually fired.
    func notifyAttachCompleted() {
        onMutation?()
    }

    // MARK: - Video-switch bridge (activity-entry-video-switch-cache-and-hide-ios)

    /// Pure: the switch-arrival override lookup — `cache[videoId]` when `videoId` is
    /// known, `nil` (hide) otherwise. `nil` `videoId` also resolves to `nil` (no
    /// lookup possible). Extracted so this decision is directly unit-testable with
    /// plain dictionaries, without constructing `DefaultActiveEvent` or a fake
    /// provider (docs/unit-test-discipline.md).
    static func resolveSwitchOverride(videoId: String?, cache: [String: LBActiveEvent]) -> LBActiveEvent? {
        guard let videoId = videoId else { return nil }
        return cache[videoId]
    }

    /// Pure: insert-or-update `videoId`'s cache entry with `activity` — a `nil`
    /// `activity` OR a `nil` `videoId` is a no-op (nothing worth remembering,
    /// mirrors `VideoFeedSnapshotCache.save`'s "empty history → skip" guard).
    static func remembering(videoId: String?, activity: LBActiveEvent?,
                            into cache: [String: LBActiveEvent]) -> [String: LBActiveEvent] {
        guard let videoId = videoId, let activity = activity else { return cache }
        var cache = cache
        cache[videoId] = activity
        return cache
    }

    /// Video-switch LEAVING half (`DefaultPlayerTemplate.handleVideoSwitch`'s `from`
    /// side): remember `videoId`'s CURRENT `currentActivity` for a possible later
    /// switch-back. MUST be called BEFORE `applySwitchOverride` changes state (reads
    /// `currentActivity` at the moment of leaving, per `remembering`'s "skip when
    /// nil" guard — nothing to remember when there was no activity to leave behind).
    func rememberSnapshot(videoId: String?) {
        snapshotsByVideoId = Self.remembering(videoId: videoId, activity: currentActivity,
                                              into: snapshotsByVideoId)
    }

    /// Video-switch ARRIVING half: immediately override `currentActivity` for the
    /// NEW video — a cached snapshot (already-visited this session) or `nil`
    /// (never-visited, or left with no activity) — bridging the display until the
    /// next poll round settles the real truth (`clearSwitchOverride`). Fires
    /// `onMutation` exactly once, regardless of whether the resolved override is a
    /// hide or a restore (both are a real, immediate state change vs. whatever was
    /// showing for the OUTGOING video a moment ago).
    ///
    /// A `nil` `videoId` (existing no-arg `handleVideoSwitch()` call sites — no
    /// destination known) is a deliberate NO-OP: it does NOT apply a "hide"
    /// override, leaving `switchOverride`/`currentActivity`/`activities`/the page
    /// index exactly as they were. This preserves this call shape's pre-existing
    /// behavior (`handleVideoSwitch` never touched `activeEvent` at all before this
    /// change) — see spec.md Scenario "省略 from/to 維持既有行為".
    ///
    /// Also resets `rawActivityPageIndex` to `0` on every REAL switch-arrival
    /// (multi-activity pagination design.md D5) — pagination is a per-video
    /// concept, so an arriving video MUST NOT inherit the outgoing video's page
    /// position, even in the (coincidental, meaningless) case where the old raw
    /// index would still happen to fall inside the new list's valid range.
    func applySwitchOverride(videoId: String?) {
        guard let videoId = videoId else { return }
        switchOverride = Self.resolveSwitchOverride(videoId: videoId, cache: snapshotsByVideoId)
        rawActivityPageIndex = 0
        onMutation?()
    }

    /// One poll round for the CURRENT video just landed (`DefaultPlayerTemplate
    /// .handlePollReceived`, fires on EVERY poll round regardless of content) — drop
    /// any still-pending switch override so `currentActivity` resumes pure live
    /// passthrough (design.md D2). This is what bounds the override to AT MOST one
    /// poll cycle, no matter whether that round's `activeEvents()` truth turns out
    /// to match the override or not — the exact mechanism that keeps this from
    /// reintroducing the "cached forever" risk the original D1 rejected. No-op
    /// (does NOT fire `onMutation`) when no override is pending — the ordinary
    /// steady-state case for the vast majority of poll rounds in a session.
    func clearSwitchOverride() {
        guard switchOverride != nil else { return }
        switchOverride = nil
        onMutation?()
    }
}
