import Foundation

/// Streak counter for consecutive complete days. A "complete day" is
/// `DailyLock.isComplete(date:)` returning true for that date.
///
/// Persistence lives in App Group so the widget can read the current
/// streak number without touching UserDefaults.standard.
struct StreakState: Codable {
    var current: Int
    var longest: Int
    var lastCompleteDate: String?  // YYYY-MM-DD

    static let empty = StreakState(current: 0, longest: 0, lastCompleteDate: nil)

    // MARK: - Persistence

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let key = "streak_state"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> StreakState {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(StreakState.self, from: data) else {
            return .empty
        }
        return s
    }

    static func save(_ s: StreakState) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: - Recompute

    /// Walk backwards from today, counting consecutive complete days.
    /// Today doesn't have to be complete yet — if yesterday was complete,
    /// the streak is the run ending yesterday and continues incrementing
    /// when today completes.
    @discardableResult
    static func refresh(now: Date = Date()) -> StreakState {
        let cal = Calendar.current
        var current = StreakState.load()

        // Start from today. If today is complete, count it; else start from yesterday.
        var cursor = cal.startOfDay(for: now)
        var count = 0

        if DailyLock.isComplete(date: cursor) {
            count += 1
        } else {
            // step back one to start counting from yesterday
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        // Walk back consecutive complete days.
        while DailyLock.isComplete(date: cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        current.current = count
        current.longest = max(current.longest, count)

        // Track the most-recent complete date for "starting over · N days
        // was your last run" messaging.
        if DailyLock.isComplete(date: cal.startOfDay(for: now)) {
            current.lastCompleteDate = formatted(now)
        }

        save(current)
        return current
    }

    private static func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
