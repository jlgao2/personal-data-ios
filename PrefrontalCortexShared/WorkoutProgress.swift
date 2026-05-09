import Foundation

/// Mirrors the per-day per-exercise per-set storage that
/// WorkoutSessionView's `markComplete` writes. Used by:
///   - WorkoutSessionView (when user taps a preset in the app)
///   - The lock-screen AppIntents (when user taps a stage button)
///
/// Both paths converge here so the underlying UserDefaults state stays
/// consistent regardless of where the tap came from.
enum WorkoutProgress {

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static func todayDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private static var stateKey: String { "workout_\(todayDateString())" }

    struct SetEntry: Codable, Equatable {
        var weight: Double
        var reps: Int
        var completed: Bool
        var bandColor: String? = nil
    }

    static func loadAll() -> [String: [SetEntry]] {
        guard let data = defaults.data(forKey: stateKey),
              let map = try? JSONDecoder().decode([String: [SetEntry]].self, from: data) else {
            return [:]
        }
        return map
    }

    static func completeSet(exerciseKey: String, setIndex: Int,
                            weight: Double, reps: Int, bandColor: String? = nil) {
        var all = loadAll()
        guard var arr = all[exerciseKey], setIndex < arr.count else { return }
        arr[setIndex].weight = weight
        arr[setIndex].reps = reps
        arr[setIndex].bandColor = bandColor
        arr[setIndex].completed = true

        let next = setIndex + 1
        if next < arr.count && !arr[next].completed {
            arr[next].weight = weight
            arr[next].reps = reps
            arr[next].bandColor = bandColor
        }
        all[exerciseKey] = arr

        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: stateKey)
        }

        if bandColor != nil {
            defaults.set(bandColor, forKey: "band_\(exerciseKey)")
        } else {
            defaults.set(weight, forKey: "weight_\(exerciseKey)")
        }
    }
}
