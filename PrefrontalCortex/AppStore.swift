import Foundation
import HealthKit

@MainActor
final class AppStore: ObservableObject {
    @Published var bundle: IOSBundle?
    @Published var liveValues: [String: Double] = [:]
    @Published var loading = true
    @Published var lastError: String?
    @Published var lastUploadResult: String?
    @Published var lastTransportError: TransportError?
    @Published var pendingAchievements: [Achievement] = []

    /// Fetch today's HKWorkout entries, POST any new ones to /v1/sessions,
    /// and mark the daily-lock workout slot done if at least one ≥10 min
    /// workout exists today.
    private func pullHealthKitWorkouts() async {
        let rows = await SampleExporter.fetchTodayWorkouts()
        guard !rows.isEmpty else { return }

        if await TransportSettings.shared.isConfigured {
            _ = try? await TransportClient.shared.uploadSessions(rows)
        }

        if !DailyLock.isWorkoutDone() {
            DailyLock.setWorkoutDone(source: .hk)
        }
    }

    private func evaluateGameState() {
        let newlyUnlocked = Achievements.refresh()
        if !newlyUnlocked.isEmpty {
            let achs = newlyUnlocked.compactMap { id in
                Achievements.all.first(where: { $0.id == id })
            }
            pendingAchievements.append(contentsOf: achs)
        }
        _ = StreakState.refresh()
    }

    func uploadTodaySamples() async {
        if let msg = await SampleExporter.uploadDaily() {
            lastUploadResult = msg
        } else {
            lastUploadResult = "Set laptop URL + token in Settings first"
        }
    }

    /// Lighter-weight than bootstrap(): no auth requests, no calendar/notification
    /// spam, no loading-flash. Refreshes the bundle, live HK values, and widget
    /// snapshot on foreground transition.
    func refreshOnForeground() async {
        await CalendarStore.shared.loadUpcoming()
        do {
            bundle = try await DataLoader.shared.loadBundle()
            lastTransportError = nil
        } catch let e as TransportError {
            lastTransportError = e
        } catch {
            // non-transport errors are surfaced on next bootstrap
        }
        await refreshLive()
        if let b = bundle {
            WidgetSnapshotWriter.update(from: b)
        }
        await pullHealthKitWorkouts()
        evaluateGameState()
    }

    func bootstrap() async {
        loading = true
        if #available(iOS 16.2, *) {
            WorkoutLiveActivity.cleanupOrphans()
        }
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
            lastTransportError = nil
        } catch let e as TransportError {
            lastTransportError = e
            lastError = e.localizedDescription
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
        await pullHealthKitWorkouts()
        evaluateGameState()
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
