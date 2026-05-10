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

        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            if isComplete {
                await activity.end(
                    ActivityContent(state: content, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(30))
                )
            } else {
                await activity.update(
                    ActivityContent(state: content, staleDate: nil)
                )
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
