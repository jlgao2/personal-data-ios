import Foundation

/// One canonical deviation, persisted as a single JSON-encoded UserDefaults
/// value per (surface, date). Mirrors the row schema of
/// `data/parquet/events/deviations-YYYY-MM.parquet`.
struct DeviationEntry: Codable, Equatable {
    var ts: Date
    var surface: Surface
    var surfaceID: String?
    var direction: Direction
    var cause: Cause?
    var prescribed: String
    var actual: String
    var actualQuant: Double?
    var lockIn: Bool
    var note: String?

    enum Surface: String, Codable, CaseIterable {
        case workout
        case suppsAM       = "supps_am"
        case suppsPM       = "supps_pm"
        case mindfulEating = "mindful_eating"
        case actionCard    = "action_card"
        case adaptedSwap   = "adapted_swap"
    }
    enum Direction: String, Codable, CaseIterable {
        case didLess        = "did_less"
        case didMore        = "did_more"
        case didDifferent   = "did_different"
        case didSkip        = "did_skip"
        case didOutsidePlan = "did_outside_plan"
    }
    enum Cause: String, Codable, CaseIterable {
        case feltFresh     = "felt_fresh"
        case feltTired     = "felt_tired"
        case pain
        case weather
        case schedule
        case traveling
        case sick
        case bored
        case intuition
        case scheduledRest = "scheduled_rest"
        case noReason      = "no_reason"
    }
}

/// Wraps the App-Group keys for deviations. One entry per (surface, date).
/// Re-tapping replaces the prior entry for that (surface, date).
enum DeviationStore {

    // MARK: - App Group

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.string(from: date)
    }

    private static func key(surface: DeviationEntry.Surface, date: Date) -> String {
        "deviation_\(surface.rawValue)_\(dateString(date))"
    }

    private static let migrationFlagKey = "did_migrate_skip_keys_v1"
    private static let altHistoryKey    = "deviation_alt_history_v1"
    private static let todayWorkoutsKey = "deviation_today_workouts_v1"

    /// One row per HK/Garmin workout that landed today, populated by AppStore
    /// from `bundle.workouts`. Used by the home-screen "today's workout"
    /// indicator AND by DeviationSheet's "what instead?" pre-fill so the
    /// sport you actually did is the first chip.
    ///
    /// `date` carries the workout's local start-of-day so reads can filter
    /// to "today" automatically — yesterday's entries fall off without an
    /// explicit clear call, which avoids a class of date-rollover bugs.
    struct TodayWorkout: Codable, Equatable {
        var sport: String          // pretty-cased, e.g. "Cycling"
        var durationMin: Int
        var date: Date             // local start-of-day for the workout
    }

    // MARK: - Read / write

    static func entry(for surface: DeviationEntry.Surface,
                      date: Date = Date()) -> DeviationEntry? {
        guard let data = defaults.data(forKey: key(surface: surface, date: date)),
              let entry = try? JSONDecoder().decode(DeviationEntry.self, from: data)
        else { return nil }
        return entry
    }

    @discardableResult
    static func record(_ entry: DeviationEntry,
                       date: Date = Date()) -> Bool {
        guard let data = try? JSONEncoder().encode(entry) else { return false }
        defaults.set(data, forKey: key(surface: entry.surface, date: date))
        return true
    }

    static func clear(surface: DeviationEntry.Surface, date: Date = Date()) {
        defaults.removeObject(forKey: key(surface: surface, date: date))
    }

    // MARK: - client_id

    /// `dev-<yyyymmdd>-<surface>-<surface_id?>` per spec.
    static func clientID(surface: DeviationEntry.Surface,
                         surfaceID: String?,
                         date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        let trailing = surfaceID?.trimmingCharacters(in: .whitespaces) ?? ""
        return "dev-\(f.string(from: date))-\(surface.rawValue)-\(trailing)"
    }

    // MARK: - Top-alternates picker source

    /// 90-day rolling sport-frequency map populated by AppStore on bundle pull.
    /// Returns up to `limit` sport names, descending by count.
    static func topAlternates(limit: Int = 4) -> [String] {
        guard let data = defaults.data(forKey: altHistoryKey),
              let map  = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [] }
        return map.sorted { $0.value > $1.value }
                  .prefix(limit)
                  .map { $0.key }
    }

    /// Refresh the "what instead" picker source from a 90-day workout history.
    /// Caller passes `(sport, count)` pairs from the bundle's workouts list +
    /// any HK pulls. Idempotent; overwrites the prior map.
    static func setAlternateHistory(_ counts: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        defaults.set(data, forKey: altHistoryKey)
    }

    // MARK: - Today's HK workouts

    /// Today's logged workouts (from `bundle.workouts` filtered to today).
    /// Populated by AppStore alongside the 90-day alternate history.
    /// Filters by `row.date` so stale entries from prior days disappear
    /// automatically on date rollover without an explicit clear call.
    static func todayWorkouts() -> [TodayWorkout] {
        guard let data = defaults.data(forKey: todayWorkoutsKey),
              let rows = try? JSONDecoder().decode([TodayWorkout].self, from: data)
        else { return [] }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        return rows.filter { cal.isDate($0.date, inSameDayAs: todayStart) }
    }

    static func setTodayWorkouts(_ rows: [TodayWorkout]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        defaults.set(data, forKey: todayWorkoutsKey)
    }

    // MARK: - Legacy migration

    /// Read every `workout_skip_reason_<YYYY-MM-DD>` key from App-Group
    /// UserDefaults; emit a Deviation row per key with `direction=did_skip`
    /// and a `cause` mapped from the legacy reason; then delete the legacy
    /// keys. Guarded by `did_migrate_skip_keys_v1` — runs at most once.
    static func migrateLegacySkipKeys() {
        if defaults.bool(forKey: migrationFlagKey) { return }

        let prefix = "workout_skip_reason_"
        let allKeys = defaults.dictionaryRepresentation().keys
        for k in allKeys where k.hasPrefix(prefix) {
            let dateString = String(k.dropFirst(prefix.count))
            guard let reason = defaults.string(forKey: k) else { continue }
            let cause = Self.causeForLegacyReason(reason)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            guard let day = f.date(from: dateString) else { continue }

            let entry = DeviationEntry(
                ts:           day,
                surface:      .workout,
                surfaceID:    nil,
                direction:    .didSkip,
                cause:        cause,
                prescribed:   "",
                actual:       "",
                actualQuant:  nil,
                lockIn:       false,
                note:         nil
            )
            record(entry, date: day)
            defaults.removeObject(forKey: k)
        }

        defaults.set(true, forKey: migrationFlagKey)
    }

    private static func causeForLegacyReason(_ reason: String) -> DeviationEntry.Cause? {
        switch reason.lowercased() {
        case "sick":            return .sick
        case "traveling":       return .traveling
        case "busy":            return .schedule
        case "unmotivated":     return .feltTired
        case "injury":          return .pain
        case "scheduled rest":  return .scheduledRest
        default:                return .noReason
        }
    }
}
