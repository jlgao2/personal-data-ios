import ActivityKit
import Foundation
import WidgetKit

/// Static facade for the workout Live Activity, owned by the host app.
///
/// Single-activity invariant: `start(...)` always calls `endAll(immediate:
/// true)` first so a stale activity from a previous session can't shadow
/// the new one. `cleanupOrphans()` runs from `AppStore.bootstrap` and ends
/// any activity whose `workoutStartedAt` is older than 4 hours.
///
/// All updates are local — no APNs / push token required. The widget
/// process drives mid-session updates via `WorkoutLiveActivityRefresher`
/// (in the shared module) so a lock-screen tap doesn't have to round-trip
/// through the host.
@available(iOS 16.2, *)
enum WorkoutLiveActivity {

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let bannerSeenKey = "liveActivity_disabled_seen_v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Are Live Activities currently allowed by the user? `false` means
    /// the user toggled them off in Settings → Notifications. We never
    /// hard-fail on this — the rectangular widget remains the fallback
    /// and we surface a one-time inline banner pointing to Settings.
    static var isAuthorized: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start a new activity for the in-progress workout. Idempotent: if
    /// an activity already exists, refresh it in place rather than
    /// requesting a duplicate.
    static func start(state: LockScreenWorkoutState, title: String) {
        guard isAuthorized else {
            // Surface the one-time disabled banner on next render.
            defaults.set(true, forKey: bannerSeenKey)
            return
        }

        // Handover from band activity → workout activity. Two stacked
        // Live Activities clutter the lock screen; the workout one takes
        // over for the duration of the session. Band activity restarts
        // from `endAll(immediate:)` below when the workout ends.
        Task { await BandLiveActivity.endAll() }

        // Single-activity invariant — ensure no leftover from a prior
        // session (or a crash mid-session) is still alive.
        if let existing = Activity<WorkoutLiveActivityAttributes>.activities.first {
            // If attrs match (same workoutStartedAt window), update; else end + restart.
            let mins = -existing.attributes.workoutStartedAt.timeIntervalSinceNow / 60
            if mins < 240 {
                Task { await refresh() }
                return
            }
            Task { await endAll(immediate: true) }
        }

        let attrs = WorkoutLiveActivityAttributes(
            workoutStartedAt: Date(),
            workoutTitle: title
        )
        let content = WorkoutLiveActivityAttributes.ContentState.from(state)

        do {
            _ = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: content, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Surfacing this anywhere except logs is overkill — the
            // widget is the fallback and there's no recovery action.
            print("WorkoutLiveActivity.start failed: \(error)")
        }
    }

    /// Update every active workout activity from the current store state.
    static func refresh() async {
        await WorkoutLiveActivityRefresher.refresh()
    }

    /// End every active workout activity. `immediate=true` dismisses
    /// instantly; `false` schedules a 30s grace via `.after(...)` so the
    /// user can read the completion banner. In either case the band
    /// activity comes back online — once the workout exits, the lock
    /// screen returns to showing the current TimeBand.
    static func endAll(immediate: Bool) async {
        if immediate {
            await WorkoutLiveActivityRefresher.endAllImmediate()
            BandLiveActivity.ensureRunning()
            return
        }
        let content = WorkoutLiveActivityAttributes.ContentState.from(
            LockScreenWorkoutStore.load(), isComplete: true
        )
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: content, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
        }
        BandLiveActivity.ensureRunning()
    }

    /// Defensive sweep on `AppStore.bootstrap`. If the user force-quit
    /// the app mid-workout and never came back, the activity could still
    /// be alive (ActivityKit lets them live up to 8 hours by default).
    /// 4 hours is the spec's chosen ceiling — past that, anything alive
    /// is almost certainly an orphan.
    static func cleanupOrphans(now: Date = Date()) {
        let cutoff: TimeInterval = 4 * 60 * 60
        Task {
            for activity in Activity<WorkoutLiveActivityAttributes>.activities {
                let age = now.timeIntervalSince(activity.attributes.workoutStartedAt)
                if age > cutoff {
                    let content = WorkoutLiveActivityAttributes.ContentState.from(
                        LockScreenWorkoutStore.load(), isComplete: true
                    )
                    await activity.end(
                        ActivityContent(state: content, staleDate: nil),
                        dismissalPolicy: .immediate
                    )
                }
            }
        }
    }

    /// Banner gate read by `LiveActivityDisabledBanner`.
    static var shouldShowDisabledBanner: Bool {
        guard !isAuthorized else { return false }
        return !defaults.bool(forKey: "liveActivity_banner_dismissed_v1")
    }

    static func dismissDisabledBanner() {
        defaults.set(true, forKey: "liveActivity_banner_dismissed_v1")
    }
}
