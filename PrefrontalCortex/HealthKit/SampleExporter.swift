import Foundation
import HealthKit

/// Reads recent HealthKit samples and POSTs them to the laptop's LAN sync server.
struct SampleExporter {
    /// Pull the latest reading for each sample type the laptop spine cares about.
    static func dailySamples() async -> [[String: Any]] {
        let store = HealthStore.shared
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var rows: [[String: Any]] = []

        func add(_ type: String, _ value: Double, unit: String) {
            // Drop zeros — HealthKit sometimes returns 0 when no recent data
            // exists in the lookback window (sleep, vo2max). Real values for
            // RHR / weight / BP / sleep are never 0 in any clinically-useful sense.
            guard value > 0 else { return }
            let now = ISO8601DateFormatter().string(from: Date())
            rows.append([
                "ts":     now,
                "ts_end": now,
                "source": "healthkit",
                "type":   type,
                "value":  value,
                "unit":   unit,
                "meta":   "{\"via\":\"ios_app\"}",
            ])
        }
        if let v = await store.latest(.restingHeartRate, unit: bpm, hours: 30) {
            add("heart_rate_resting", v, unit: "bpm")
        }
        if let v = await store.latest(.vo2Max, unit: HKUnit(from: "ml/(kg*min)"), hours: 24*60) {
            add("vo2max", v, unit: "mL/min·kg")
        }
        if let v = await store.latest(.bodyMass, unit: .pound(), hours: 24*30) {
            add("weight", v, unit: "lb")
        }
        if let v = await store.latest(.bloodPressureSystolic, unit: .millimeterOfMercury(), hours: 24*60) {
            add("bp_systolic", v, unit: "mmHg")
        }
        if let v = await store.latest(.bloodPressureDiastolic, unit: .millimeterOfMercury(), hours: 24*60) {
            add("bp_diastolic", v, unit: "mmHg")
        }
        if let v = await store.sleepMinutes(hours: 36) {
            add("sleep_minutes", v, unit: "min")
        }
        return rows
    }

    /// Returns a human-readable status string. nil means "transport not configured;
    /// nothing happened" — caller should treat that distinctly from a real failure.
    @discardableResult
    static func uploadDaily() async -> String? {
        let rows = await dailySamples()
        guard !rows.isEmpty else { return "No samples to upload" }
        let uploads = rows.compactMap { d -> SampleUpload? in
            guard let ts    = d["ts"]    as? String,
                  let type  = d["type"]  as? String,
                  let value = d["value"] as? Double else { return nil }
            return SampleUpload(ts: ts, type: type, value: value, unit: d["unit"] as? String)
        }
        guard !uploads.isEmpty else { return "No samples to upload" }
        do {
            try await iCloudTransport.shared.uploadSamples(uploads)
            return "Uploaded \(uploads.count) sample\(uploads.count == 1 ? "" : "s")"
        } catch {
            return "Upload failed: \(error.localizedDescription)"
        }
    }

    /// Pull today's HKWorkout entries (≥10 min) and return them as session
    /// rows ready for /v1/sessions. Each row gets a deterministic
    /// client_id so re-pulls dedupe at the laptop side.
    static func fetchTodayWorkouts() async -> [SessionUpload] {
        let store = HealthStore.shared.store
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }

        let f = ISO8601DateFormatter()
        let dateF = DateFormatter(); dateF.dateFormat = "yyyy-MM-dd"
        dateF.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = dateF.string(from: start)

        return workouts.compactMap { w -> SessionUpload? in
            guard w.duration >= 600 else { return nil }
            let sport = mapWorkoutType(w.workoutActivityType)
            return SessionUpload(
                client_id:    "hk-\(dateStr)-\(sport)",
                ts:           f.string(from: w.startDate),
                sport:        sport,
                duration_min: Int((w.duration / 60).rounded()),
                rpe:          nil,
                note:         "auto-logged from HealthKit"
            )
        }
    }

    private static func mapWorkoutType(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running, .crossCountrySkiing:   return "RUNNING"
        case .cycling:                        return "CYCLING"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:     return "STRENGTH_TRAINING"
        case .yoga:                           return "YOGA"
        case .swimming:                       return "SWIMMING"
        case .hiking:                         return "HIKING"
        case .walking:                        return "WALKING"
        case .downhillSkiing:                 return "ALPINE_SKIING"
        default:                              return "OTHER"
        }
    }
}
