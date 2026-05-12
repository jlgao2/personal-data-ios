import Foundation

/// Snapshot of the in-progress workout that both the iOS app and the widget
/// extension can read/write. Persisted as JSON in the App Group container.
struct LockScreenWorkoutState: Codable {
    var inProgress: Bool
    var exerciseKey: String
    var exerciseName: String
    var setIndex: Int
    var totalSets: Int
    var lastWeight: Double
    var lastReps: Int
    var stage: Stage
    var stagedWeight: Double?
    var mode: Mode
    var bandColor: String?
    var unit: String
    /// Remaining exercises after the current one, populated by the host
    /// app's `syncToLockScreen`. The widget-extension intent pops off the
    /// front when the user finishes the current exercise's last set so the
    /// Live Activity advances on-screen instead of ending the workout.
    /// Empty (default) means the current exercise is the last one.
    var queue: [QueuedExercise] = []

    struct QueuedExercise: Codable {
        var exerciseKey: String
        var exerciseName: String
        var totalSets: Int
        var mode: Mode
        var lastWeight: Double
        var lastReps: Int
        var bandColor: String?
    }

    enum Stage: String, Codable { case weight, reps }
    enum Mode: String, Codable { case free, band, time, amrap }

    static let idle = LockScreenWorkoutState(
        inProgress: false,
        exerciseKey: "",
        exerciseName: "",
        setIndex: 0,
        totalSets: 0,
        lastWeight: 0,
        lastReps: 0,
        stage: .weight,
        stagedWeight: nil,
        mode: .free,
        bandColor: nil,
        unit: "lb",
        queue: []
    )
}

enum LockScreenWorkoutStore {
    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let filename = "widget_workout_state.json"

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    // In-memory cache keyed by file mtime so cross-process writes invalidate it.
    private static var cached: (mtime: Date, state: LockScreenWorkoutState)?
    private static let cacheLock = NSLock()

    private static func mtime(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    static func load() -> LockScreenWorkoutState {
        guard let url else { return .idle }
        guard let mtime = mtime(of: url) else {
            // File doesn't exist.
            return .idle
        }
        cacheLock.lock()
        if let c = cached, c.mtime == mtime {
            let s = c.state
            cacheLock.unlock()
            return s
        }
        cacheLock.unlock()

        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(LockScreenWorkoutState.self, from: data) else {
            return .idle
        }
        cacheLock.lock()
        cached = (mtime, s)
        cacheLock.unlock()
        return s
    }

    static func save(_ s: LockScreenWorkoutState) {
        guard let url else { return }
        if let data = try? JSONEncoder().encode(s) {
            do {
                try data.write(to: url, options: .atomic)
                if let newMtime = mtime(of: url) {
                    cacheLock.lock()
                    cached = (newMtime, s)
                    cacheLock.unlock()
                }
            } catch {
                // Write failed; leave cache as-is.
            }
        }
    }

    static func clear() { save(.idle) }
}
