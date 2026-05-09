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
        unit: "lb"
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

    static func load() -> LockScreenWorkoutState {
        guard let url, let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(LockScreenWorkoutState.self, from: data) else {
            return .idle
        }
        return s
    }

    static func save(_ s: LockScreenWorkoutState) {
        guard let url else { return }
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func clear() { save(.idle) }
}
