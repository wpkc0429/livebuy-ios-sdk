import LivebuySDK

// MARK: - DefaultActiveEvent — 目前進行中活動狀態（live-activity-entry-template）
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template 目前進行中活動狀態（`LBActivitySheet` 行為）"
//   § "Default Template 加入目前活動（轉發既有 joinEvent）"
// Design: design.md D1 (即時讀穿、不快取) / D2 (attach 時補一次通知) / D3
//         (join 純轉發既有 joinEvent，見下方「為什麼 joinCurrentActivity() 不在這裡」)
//         / D4（直接暴露 public `LBActiveEvent`，不建中介型別）.
//
// Behaviour / view-model layer ONLY (no pixels). The host draws `LBActivitySheet`
// (`{title, prizeName, keyword}`，見 `design/templates/minimal/moments.jsx`)
// bound to `currentActivity`, and its「立即參加」CTA calls
// `DefaultPlayerTemplate.joinCurrentActivity()`. core stays headless: it never
// maintains a "current activity" merged state and never renders an entry / sheet.

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

    public init(provider: ActiveEventProviding?) {
        self.provider = provider
    }

    /// The single in-progress activity a host should surface (design.md D1:
    /// aligned with the `LBActivitySheet` design's "one activity entry at a
    /// time" assumption — simultaneous activities are out of scope, see
    /// proposal.md "明確不做").
    ///
    /// **Computed, NOT stored / cached.** Every read re-queries
    /// `provider.activeEvents()` fresh and returns its FIRST element (`nil`
    /// when empty). This is deliberate: core has no "activity ended" push
    /// event (`ACTIVE_EVENT_STARTED` fires only when an activity BEGINS), so
    /// caching this into an ordinary stored property — set once on
    /// `ACTIVE_EVENT_STARTED` — would go stale FOREVER once the activity
    /// actually ends, because nothing would ever clear it. Reading straight
    /// through to core's own poll-refreshed snapshot means the value is
    /// always correct the moment `activeEvents()` itself drops the finished
    /// entry — no clearing logic needed here at all.
    ///
    /// Known, accepted limitation (design.md D1): this alone does not make
    /// the HOST repaint the instant an activity ends — `onMutation` only
    /// fires on `ACTIVE_EVENT_STARTED` / template attach (see
    /// `notifyActivityStarted()` / `notifyAttachCompleted()`) — so a finished
    /// activity's entry may stay visually rendered until the next
    /// host-triggered redraw for any other reason. Accepted trade-off, not an
    /// oversight — see design.md D1 for the full cost/benefit discussion.
    public var currentActivity: LBActiveEvent? {
        provider?.activeEvents().first
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
}
