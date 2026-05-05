import Foundation
import HealthKit

@MainActor
final class AppStore: ObservableObject {
    @Published var bundle: IOSBundle?
    @Published var liveValues: [String: Double] = [:]
    @Published var loading = true
    @Published var lastError: String?
    @Published var lastUploadResult: String?

    func uploadTodaySamples() async {
        if let url = await SampleExporter.uploadDaily() {
            lastUploadResult = "Uploaded \(url.lastPathComponent)"
        } else {
            lastUploadResult = "No samples uploaded (no HK auth or no recent data)"
        }
    }

    func bootstrap() async {
        loading = true
        do {
            try await HealthStore.shared.authorize()
        } catch {
            lastError = "HealthKit authorization failed: \(error.localizedDescription)"
        }
        _ = await NotificationManager.shared.requestAuthorization()
        // Calendar — silently load if previously authorized
        await CalendarStore.shared.loadUpcoming()
        do {
            bundle = try await DataLoader.shared.loadBundle()
        } catch {
            lastError = "Bundle load failed: \(error.localizedDescription)"
        }
        await refreshLive()
        // Push a slim snapshot to the App Group so widgets can read it.
        if let b = bundle {
            WidgetSnapshotWriter.update(from: b)
        }
        if let cards = bundle?.action_loop {
            let fired = await NotificationManager.shared.diffAndNotify(
                cards: cards, live: liveValues)
            if !fired.isEmpty {
                lastUploadResult = "Notified: \(fired.count) card\(fired.count == 1 ? "" : "s") changed state"
            }
        }
        loading = false
    }

    func refreshLive() async {
        var v: [String: Double] = [:]
        let bpm = HKUnit.count().unitDivided(by: .minute())
        if let rhr = await HealthStore.shared.latest(.restingHeartRate, unit: bpm, hours: 48) {
            v["heart_rate_resting"] = rhr
        }
        if let vo2 = await HealthStore.shared.latest(.vo2Max,
                       unit: HKUnit(from: "ml/(kg*min)"), hours: 24 * 60) {
            v["vo2max"] = vo2
        }
        if let weight = await HealthStore.shared.latest(.bodyMass,
                          unit: .pound(), hours: 24 * 30) {
            v["weight"] = weight
        }
        if let sysBP = await HealthStore.shared.latest(.bloodPressureSystolic,
                         unit: .millimeterOfMercury(), hours: 24 * 60) {
            v["bp_systolic"] = sysBP
        }
        if let diaBP = await HealthStore.shared.latest(.bloodPressureDiastolic,
                         unit: .millimeterOfMercury(), hours: 24 * 60) {
            v["bp_diastolic"] = diaBP
        }
        if let sleep = await HealthStore.shared.sleepMinutes(hours: 36) {
            v["sleep_minutes"] = sleep
        }
        liveValues = v
    }
}
