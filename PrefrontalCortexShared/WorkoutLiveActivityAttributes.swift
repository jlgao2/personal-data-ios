import ActivityKit
import Foundation

/// ActivityKit attributes for the in-progress workout Live Activity.
///
/// `WorkoutLiveActivityAttributes` carries the *static* properties that
/// don't change for the lifetime of the activity (start time, title).
/// Everything mutable lives in `ContentState`, which mirrors a strict
/// subset of `LockScreenWorkoutState`. ActivityKit caps `ContentState`
/// payloads at 4KB per update, so we keep the surface narrow.
struct WorkoutLiveActivityAttributes: ActivityAttributes {

    /// Wall-clock when the activity (and the workout session) was started.
    /// Used by the orphan-cleanup pass on `AppStore.bootstrap` to end any
    /// activity older than 4 hours.
    let workoutStartedAt: Date

    /// Human label for the day, e.g. "Day 4 · Back/Biceps". Static for the
    /// life of the activity — exercise name lives in `ContentState` because
    /// it changes between sets.
    let workoutTitle: String

    /// Per-update mutable state. Strict subset of `LockScreenWorkoutState`
    /// (everything except `inProgress`, which is implicit while the activity
    /// is alive).
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var setIndex: Int
        var totalSets: Int
        var lastWeight: Double
        var lastReps: Int
        var stage: String          // "weight" | "reps"
        var stagedWeight: Double?
        var mode: String           // "free" | "band" | "time" | "amrap"
        var bandColor: String?
        var unit: String

        /// Set true on the final-set commit. Drives the "Workout complete"
        /// stale presentation + the 30s auto-dismiss timer.
        var isComplete: Bool

        /// Adapter from the App-Group store. Both the host and widget
        /// processes use this so the activity payload is identical no
        /// matter who triggered the refresh.
        static func from(_ s: LockScreenWorkoutState, isComplete: Bool = false) -> ContentState {
            ContentState(
                exerciseName: s.exerciseName,
                setIndex: s.setIndex,
                totalSets: s.totalSets,
                lastWeight: s.lastWeight,
                lastReps: s.lastReps,
                stage: s.stage.rawValue,
                stagedWeight: s.stagedWeight,
                mode: s.mode.rawValue,
                bandColor: s.bandColor,
                unit: s.unit,
                isComplete: isComplete
            )
        }
    }
}
