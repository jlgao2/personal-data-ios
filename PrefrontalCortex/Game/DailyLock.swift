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
    private static func skincareAMKey(_ date: Date) -> String    { "skincare_am_\(dateKey(date))" }
    private static func skincarePMKey(_ date: Date) -> String    { "skincare_pm_\(dateKey(date))" }
    private static func embodimentKey(_ date: Date) -> String    { "embodiment_done_\(dateKey(date))" }

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
    static func isSkincareAMDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: skincareAMKey(date))
    }
    static func isSkincarePMDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: skincarePMKey(date))
    }
    static func isEmbodimentDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: embodimentKey(date))
    }

    static func setEmbodimentDone(_ done: Bool, date: Date = Date()) {
        if done {
            defaults.set(true, forKey: embodimentKey(date))
        } else {
            defaults.removeObject(forKey: embodimentKey(date))
        }
    }

    // MARK: - Skincare mutators

    static func setSkincareAMDone(_ done: Bool, date: Date = Date()) {
        if done {
            defaults.set(true, forKey: skincareAMKey(date))
        } else {
            defaults.removeObject(forKey: skincareAMKey(date))
        }
    }
    static func setSkincarePMDone(_ done: Bool, date: Date = Date()) {
        if done {
            defaults.set(true, forKey: skincarePMKey(date))
        } else {
            defaults.removeObject(forKey: skincarePMKey(date))
        }
    }

    // MARK: - The unified gate

    /// Everything required for a "complete day" — built-in slots that
    /// aren't authorship-outside, plus every user-defined custom slot.
    /// Built-in slots use AuthorshipStore to short-circuit (outside-
    /// tagged slots don't gate). Custom slots are always self-authored
    /// (the user defined them; if they don't want it counted they can
    /// delete the slot via the editor) so they always gate.
    static func isComplete(date: Date = Date()) -> Bool {
        let builtIn =
            (AuthorshipStore.get(.workout)    == .outside || isWorkoutDone(date: date))
            && (AuthorshipStore.get(.suppsAM)    == .outside || isAMSuppsDone(date: date))
            && (AuthorshipStore.get(.suppsPM)    == .outside || isPMSuppsDone(date: date))
            && (AuthorshipStore.get(.mindful)    == .outside || isMindfulEatingDone(date: date))
            && (AuthorshipStore.get(.skincareAM) == .outside || isSkincareAMDone(date: date))
            && (AuthorshipStore.get(.skincarePM) == .outside || isSkincarePMDone(date: date))
            && (AuthorshipStore.get(.embodiment) == .outside || isEmbodimentDone(date: date))

        let custom = CustomSlotStore.load().allSatisfy {
            CustomSlotStore.isDone(slotID: $0.id, date: date)
        }

        return builtIn && custom
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

/// `.dayDidRollOver` — refresh-now signal. Fires on every scenePhase
/// .active, every TimeBand edge, and every midnight. Views that compute
/// state from `Date()` and cache it in @State subscribe to bump their
/// refresh tick. Cheap to fire often; subscribers must be idempotent.
///
/// `.calendarDayChanged` — actual-rollover signal. Fires ONLY when the
/// calendar date crossed (midnight while the app was open, or the first
/// scenePhase.active after the date changed). Distinct from
/// `.dayDidRollOver` because once-per-day handlers (DayCloseView,
/// "yesterday's summary" surfaces) MUST NOT trigger on band edges or
/// every foreground — that was the bug where DayCloseView popped open
/// on every band crossing.
extension Notification.Name {
    static let dayDidRollOver     = Notification.Name("PrefrontalCortex.dayDidRollOver")
    static let calendarDayChanged = Notification.Name("PrefrontalCortex.calendarDayChanged")
}
