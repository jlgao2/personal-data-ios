import Foundation

/// The 12 achievements. Pure-function condition evaluators that take the
/// current streak + recent daily-lock history and return whether each
/// achievement should be unlocked. Newly-firing ones return from `refresh()`
/// so the UI can show a toast.
struct Achievement: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String           // SF Symbol
    let condition: (Context) -> Bool

    struct Context {
        let now: Date
        let streak: StreakState
        /// Last 30 days' DailyLock.isComplete results, indexed by YYYY-MM-DD.
        let history: [String: Bool]
        /// Last 30 days' workout sources, indexed by YYYY-MM-DD.
        let sources: [String: DailyLock.WorkoutSource]
        /// Last 30 days' mindful-eating booleans (own track, not full streak).
        let mindful: [String: Bool]
    }
}

enum Achievements {

    // MARK: - Catalog

    static let all: [Achievement] = [
        // Streak milestones
        Achievement(
            id: "first_step",
            name: "First step",
            description: "Logged your first complete day.",
            icon: "figure.walk",
            condition: { $0.streak.longest >= 1 }
        ),
        Achievement(
            id: "week_of_work",
            name: "Week of work",
            description: "7-day streak.",
            icon: "7.circle",
            condition: { $0.streak.longest >= 7 }
        ),
        Achievement(
            id: "tendril",
            name: "Tendril",
            description: "30-day streak.",
            icon: "leaf",
            condition: { $0.streak.longest >= 30 }
        ),
        Achievement(
            id: "roots",
            name: "Roots",
            description: "90-day streak.",
            icon: "tree",
            condition: { $0.streak.longest >= 90 }
        ),
        Achievement(
            id: "pillar",
            name: "Pillar",
            description: "365-day streak.",
            icon: "building.columns",
            condition: { $0.streak.longest >= 365 }
        ),

        // Volume milestones
        Achievement(
            id: "volume_keeper",
            name: "Volume keeper",
            description: "100 total complete days.",
            icon: "hexagon.fill",
            condition: { $0.history.values.filter { $0 }.count >= 100 }
        ),
        Achievement(
            id: "iron_line",
            name: "Iron line",
            description: "365 total complete days.",
            icon: "medal",
            condition: { $0.history.values.filter { $0 }.count >= 365 }
        ),

        // Behavior signals
        Achievement(
            id: "honest_break",
            name: "Honest break",
            description: "Used skip-with-reason 3+ times in a 30-day window.",
            icon: "hand.raised",
            condition: { ctx in
                ctx.sources.values.filter { $0 == .skip }.count >= 3
            }
        ),
        Achievement(
            id: "bounce_back",
            name: "Bounce-back",
            description: "Restarted a streak within 3 days of breaking it.",
            icon: "arrow.uturn.up",
            condition: { ctx in
                let cal = Calendar.current
                let today = cal.startOfDay(for: ctx.now)
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                for back in 0..<10 {
                    guard let recent = cal.date(byAdding: .day, value: -back, to: today),
                          ctx.history[f.string(from: recent)] == true else { continue }
                    for gap in 1...4 {
                        guard let earlier = cal.date(byAdding: .day, value: -gap, to: recent),
                              ctx.history[f.string(from: earlier)] == true else { continue }
                        if gap >= 2 && gap <= 4 { return true }
                    }
                }
                return false
            }
        ),
        Achievement(
            id: "quiet_rest",
            name: "Quiet rest",
            description: "4 consecutive Sunday rest days acknowledged.",
            icon: "moon.stars",
            condition: { ctx in
                let cal = Calendar.current
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                var consecutive = 0
                var cursor = cal.startOfDay(for: ctx.now)
                for _ in 0..<60 {
                    let weekday = cal.component(.weekday, from: cursor)  // 1=Sun
                    if weekday == 1 {
                        let key = f.string(from: cursor)
                        let restAck = (ctx.sources[key] == .rest_ack)
                        let skipOnSun = (ctx.sources[key] == .skip && ctx.history[key] == true)
                        if restAck || skipOnSun {
                            consecutive += 1
                            if consecutive >= 4 { return true }
                        } else {
                            consecutive = 0
                        }
                    }
                    guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = prev
                }
                return false
            }
        ),
        Achievement(
            id: "mindful_month",
            name: "Mindful month",
            description: "30-day mindful-eating streak.",
            icon: "eye.circle",
            condition: { ctx in
                let cal = Calendar.current
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                var cursor = cal.startOfDay(for: ctx.now)
                var run = 0
                for _ in 0..<60 {
                    let key = f.string(from: cursor)
                    if ctx.mindful[key] == true {
                        run += 1
                        if run >= 30 { return true }
                    } else {
                        run = 0
                    }
                    guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = prev
                }
                return false
            }
        ),
        Achievement(
            id: "clean_week",
            name: "Clean week",
            description: "Full Mon-Sun of supps both AM and PM.",
            icon: "checkmark.seal",
            condition: { ctx in
                let cal = Calendar.current
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                let today = cal.startOfDay(for: ctx.now)
                let defaults = UserDefaults(suiteName: "group.com.jlgao.PrefrontalCortex") ?? .standard
                for back in 0..<60 {
                    guard let cursor = cal.date(byAdding: .day, value: -back, to: today) else { break }
                    if cal.component(.weekday, from: cursor) != 1 { continue } // 1 = Sunday
                    var allClean = true
                    for offset in 0...6 {
                        guard let day = cal.date(byAdding: .day, value: -offset, to: cursor) else {
                            allClean = false; break
                        }
                        let am = defaults.bool(forKey: "stack_period_\(f.string(from: day))_morning")
                        let pm = defaults.bool(forKey: "stack_period_\(f.string(from: day))_evening")
                        if !am || !pm { allClean = false; break }
                    }
                    if allClean { return true }
                }
                return false
            }
        ),
    ]

    // MARK: - State

    struct State: Codable {
        var unlocked: [String: String] = [:]  // id → unlock-date YYYY-MM-DD
    }

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let key = "achievement_state"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // Session-lifetime cache for State. Invalidated on save().
    private static var cachedState: State?
    private static let stateLock = NSLock()

    static func load() -> State {
        stateLock.lock()
        if let c = cachedState {
            stateLock.unlock()
            return c
        }
        stateLock.unlock()
        let loaded: State
        if let data = defaults.data(forKey: key),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            loaded = s
        } else {
            loaded = State()
        }
        stateLock.lock()
        cachedState = loaded
        stateLock.unlock()
        return loaded
    }

    static func save(_ s: State) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: key)
        }
        stateLock.lock()
        cachedState = s
        stateLock.unlock()
    }

    // MARK: - Refresh

    /// Re-evaluate every achievement. Returns ids of newly-unlocked ones
    /// (existing unlocks are not re-emitted).
    @discardableResult
    static func refresh(now: Date = Date()) -> [String] {
        let context = buildContext(now: now)
        var state = load()
        var newlyUnlocked: [String] = []
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = f.string(from: now)

        for ach in all where state.unlocked[ach.id] == nil && ach.condition(context) {
            state.unlocked[ach.id] = today
            newlyUnlocked.append(ach.id)
        }
        if !newlyUnlocked.isEmpty {
            save(state)
        }
        return newlyUnlocked
    }

    // Cached historical portion of buildContext: covers days <= yesterday.
    // Keyed by today's YYYY-MM-DD string; when the wall-clock day rolls the
    // key changes and we rebuild. Today's row is always read live.
    private struct HistoricalSnapshot {
        let todayKey: String
        let history: [String: Bool]
        let sources: [String: DailyLock.WorkoutSource]
        let mindful: [String: Bool]
    }
    private static var cachedHistory: HistoricalSnapshot?
    private static let historyLock = NSLock()

    private static func buildContext(now: Date) -> Achievement.Context {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = cal.startOfDay(for: now)
        let todayKey = f.string(from: today)

        // Pull cached historical snapshot (days <= yesterday) if it still
        // matches today's calendar day.
        historyLock.lock()
        let snapshot = cachedHistory
        historyLock.unlock()

        var history: [String: Bool]
        var sources: [String: DailyLock.WorkoutSource]
        var mindful: [String: Bool]

        if let s = snapshot, s.todayKey == todayKey {
            history = s.history
            sources = s.sources
            mindful = s.mindful
        } else {
            history = [:]
            sources = [:]
            mindful = [:]
            // back >= 1 — yesterday and older are stable for the session.
            // (Today is added live below.) Original loop covered 0..<400
            // (400 days including today); this covers 1..<400 (399 historical
            // days) + today added live → same 400-day total.
            for back in 1..<400 {
                guard let day = cal.date(byAdding: .day, value: -back, to: today) else { break }
                let key = f.string(from: day)
                history[key] = DailyLock.isComplete(date: day)
                if let src = DailyLock.workoutSource(date: day) {
                    sources[key] = src
                }
                mindful[key] = DailyLock.isMindfulEatingDone(date: day)
            }
            let newSnap = HistoricalSnapshot(
                todayKey: todayKey,
                history: history,
                sources: sources,
                mindful: mindful
            )
            historyLock.lock()
            cachedHistory = newSnap
            historyLock.unlock()
        }

        // Today is always read live — it can mutate within a session.
        history[todayKey] = DailyLock.isComplete(date: today)
        if let src = DailyLock.workoutSource(date: today) {
            sources[todayKey] = src
        } else {
            sources.removeValue(forKey: todayKey)
        }
        mindful[todayKey] = DailyLock.isMindfulEatingDone(date: today)

        return .init(now: now, streak: StreakState.load(),
                     history: history, sources: sources, mindful: mindful)
    }
}
