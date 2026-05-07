import Foundation
import HealthKit

/// Reads recent HealthKit samples and writes a JSON drop the laptop pipeline
/// will pick up on its next refresh.sh run. One file per day.
struct SampleExporter {
    private static let containerID = "iCloud.com.jlgao.PrefrontalCortex"

    /// Pull the latest reading for each sample type the laptop spine cares about.
    static func dailySamples() async -> [[String: Any]] {
        let store = HealthStore.shared
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var rows: [[String: Any]] = []

        func add(_ type: String, _ value: Double, unit: String) {
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

    /// Write a samples_YYYY-MM-DD.json drop to iCloud Drive.
    @discardableResult
    static func uploadDaily() async -> URL? {
        let rows = await dailySamples()
        guard !rows.isEmpty else { return nil }
        guard let dir = FileManager.default
            .url(forUbiquityContainerIdentifier: containerID)?
            .appendingPathComponent("Documents/ios_export") else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = dir.appendingPathComponent("samples_\(f.string(from: Date())).json")
        do {
            let data = try JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted)
            try data.write(to: url)
            return url
        } catch {
            print("SampleExporter write failed: \(error)")
            return nil
        }
    }
}
