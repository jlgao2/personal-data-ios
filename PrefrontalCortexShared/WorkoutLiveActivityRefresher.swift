import ActivityKit
import Foundation

/// Refreshes any in-flight Workout Live Activity from the current
/// `LockScreenWorkoutStore` state. Runs in whichever process called
/// it — host app on session-view changes, widget extension on a
/// lock-screen button tap. Safe to call when no activity is active
/// (it just no-ops).
enum WorkoutLiveActivityRefresher {

    /// Called from `WorkoutAppIntents.perform()` after persisting state.
    /// If the live state has rolled past the final set, end the activity
    /// with a 30-second dismissal grace so the user sees the completion
    /// before it disappears.
    @available(iOS 16.1, *)
    static func refresh() async {
        let state = LockScreenWorkoutStore.load()
        let isComplete = !state.inProgress
        let content = WorkoutLiveActivityAttributes.ContentState.from(state, isComplete: isComplete)

        let payload = ActivityContent(state: content, staleDate: nil)
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            if isComplete {
                // Belt-and-suspenders: `.update` first so the UI flips to
                // "✓ WORKOUT COMPLETE" regardless of whether `.end` reliably
                // takes effect from this process (widget-extension calls to
                // `.end` on activities started by the host app have been
                // observed to silently no-op on some iOS versions). Then
                // schedule the natural 30s dismissal.
                await activity.update(payload)
                await activity.end(
                    payload,
                    dismissalPolicy: .after(Date().addingTimeInterval(30))
                )
            } else {
                await activity.update(payload)
            }
        }
    }

    /// Force-end every active workout activity immediately. Used by the
    /// host app on `commitAndDismiss` and by `EndWorkoutIntent`.
    @available(iOS 16.1, *)
    static func endAllImmediate() async {
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
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
