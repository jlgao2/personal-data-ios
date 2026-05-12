import Foundation

/// One entry in the bundled exercise library (`Resources/exercise_library.json`).
/// Field names mirror the JSON exactly so we can decode without a custom CodingKey map.
struct ExerciseEntry: Codable {
    let key: String
    let name: String
    let mode: String                 // "free" | "band" | "time" | "amrap"
    let default_weight_lb: Double?
    let default_reps: Int?
    let default_band_color: String?  // "yellow" | "red" | "green" | "blue" | "black"
    let default_seconds: Int?
    let tags: [String]?
    let notes: String?
}

private struct ExerciseLibraryFile: Codable {
    let exercises: [ExerciseEntry]
}

/// Bundle-loaded exercise library, keyed by `entry.key` — the same string
/// `exerciseKey(_:)` in `WorkoutSessionView.swift` produces from an exercise name.
/// Lazily decoded once on first access; falls back to `[:]` on any failure so
/// the app never crashes — every consumer should keep its legacy default path.
enum ExerciseLibrary {
    static let shared: [String: ExerciseEntry] = {
        guard let url = Bundle.main.url(forResource: "exercise_library",
                                        withExtension: "json") else {
            print("[ExerciseLibrary] exercise_library.json not found in bundle; using empty library.")
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(ExerciseLibraryFile.self, from: data)
            var map: [String: ExerciseEntry] = [:]
            map.reserveCapacity(file.exercises.count)
            for entry in file.exercises {
                map[entry.key] = entry
            }
            return map
        } catch {
            print("[ExerciseLibrary] decode failed: \(error); using empty library.")
            return [:]
        }
    }()
}
