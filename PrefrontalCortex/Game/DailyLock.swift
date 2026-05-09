import Foundation

/// Per-day lock state. Wraps the existing UserDefaults keys for supps and
/// mindful eating, plus a new key for the workout slot. The four slots
/// AND-together into `isComplete(date:)`, which is the streak's daily gate.
///
/// All keys live in the App Group default suite so the widget extension
/// reads the same source of truth.
enum DailyLock {

    // MARK: - App Group

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: - Keys

    private static func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.string(from: date)
    }

    private static func workoutDoneKey(_ date: Date) -> String   { "workout_done_\(dateKey(date))" }
    private static func workoutSourceKey(_ date: Date) -> String { "workout_source_\(dateKey(date))" }
    private static func workoutSkipReasonKey(_ date: Date) -> String { "workout_skip_reason_\(dateKey(date))" }
    private static func amSuppsKey(_ date: Date) -> String       { "stack_period_\(dateKey(date))_morning" }
    private static func pmSuppsKey(_ date: Date) -> String       { "stack_period_\(dateKey(date))_evening" }
    private static func mindfulKey(_ date: Date) -> String       { "mindful_eat_\(dateKey(date))" }

    // MARK: - Source enum

    enum WorkoutSource: String {
        case hk
        case manual
        case skip
        case rest_ack
    }

    // MARK: - Per-slot reads

    static func isWorkoutDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: workoutDoneKey(date))
    }
    static func workoutSource(date: Date = Date()) -> WorkoutSource? {
        defaults.string(forKey: workoutSourceKey(date)).flatMap(WorkoutSource.init)
    }
    static func workoutSkipReason(date: Date = Date()) -> String? {
        defaults.string(forKey: workoutSkipReasonKey(date))
    }
    static func isAMSuppsDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: amSuppsKey(date))
    }
    static func isPMSuppsDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: pmSuppsKey(date))
    }
    static func isMindfulEatingDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: mindfulKey(date))
    }

    // MARK: - The unified gate

    static func isComplete(date: Date = Date()) -> Bool {
        isWorkoutDone(date: date)
            && isAMSuppsDone(date: date)
            && isPMSuppsDone(date: date)
            && isMindfulEatingDone(date: date)
    }

    // MARK: - Workout-slot mutators

    static func setWorkoutDone(source: WorkoutSource, reason: String? = nil, date: Date = Date()) {
        defaults.set(true,            forKey: workoutDoneKey(date))
        defaults.set(source.rawValue, forKey: workoutSourceKey(date))
        if let reason {
            defaults.set(reason, forKey: workoutSkipReasonKey(date))
        }
    }

    static func clearWorkoutDone(date: Date = Date()) {
        defaults.removeObject(forKey: workoutDoneKey(date))
        defaults.removeObject(forKey: workoutSourceKey(date))
        defaults.removeObject(forKey: workoutSkipReasonKey(date))
    }
}
