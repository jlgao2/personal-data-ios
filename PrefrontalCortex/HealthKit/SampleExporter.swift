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
        guard await TransportSettings.shared.isConfigured else {
            return nil
        }
        do {
            let resp = try await TransportClient.shared.uploadSamples(rows)
            return "Uploaded \(resp.written) of \(rows.count) sample\(rows.count == 1 ? "" : "s")"
        } catch {
            return "Upload failed: \(TransportClient.wrap(error).localizedDescription)"
        }
    }
}
