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
    ///
    /// Returns `true` when this call observed today's workout for the first
    /// time — i.e. `DailyLock.isWorkoutDone` was false on entry and we just
    /// flipped it. The caller uses this to know whether the bundle needs a
    /// re-fetch so the workouts list / adaptive engine reflect the new
    /// session on the same foreground instead of the next.
    @discardableResult
    private func pullHealthKitWorkouts() async -> Bool {
        let rows = await SampleExporter.fetchTodayWorkouts()
        guard !rows.isEmpty else { return false }

        // Local-first: write today's HK workouts straight into the App-Group
        // store so the home-screen `TodaysWorkoutChip` + DeviationSheet's
        // "what instead?" pre-fill render off the device's own HK data
        // without waiting for a laptop round-trip. Works even when the
        // laptop is asleep / unreachable.
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayWorkouts: [DeviationStore.TodayWorkout] = rows.map { r in
            let pretty = r.sport.replacingOccurrences(of: "_", with: " ").capitalized
            return .init(sport: pretty, durationMin: r.duration_min, date: todayStart)
        }
        if !todayWorkouts.isEmpty {
            DeviationStore.setTodayWorkouts(todayWorkouts)
        }

        // Best-effort upload to laptop. Failures here are common (laptop
        // off, different network, server down for refresh) — surface them
        // into `lastTransportError` so the TransportStatusPill flips to
        // "Laptop offline" instead of silently dropping the upload.
        if await TransportSettings.shared.isConfigured {
            do {
                _ = try await TransportClient.shared.uploadSessions(rows)
                lastTransportError = nil
            } catch let e as TransportError {
                lastTransportError = e
            } catch {
                lastTransportError = TransportClient.wrap(error)
            }
        }

        let wasAlreadyDone = DailyLock.isWorkoutDone()
        if !wasAlreadyDone {
            DailyLock.setWorkoutDone(source: .hk)
        }
        return !wasAlreadyDone
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
    ///
    /// **Ordering contract (`bootstrap` and `refreshOnForeground`):**
    ///   1. Calendar load — must run before bundle so calendar UI doesn't flash.
    ///   2. Bundle fetch — sets `lastTransportError` for the UI; may fall back
    ///      to disk cache on network failure.
    ///   3. `refreshLive` — HK queries (parallelized via async let).
    ///   4. `WidgetSnapshotWriter.update` — must run after bundle is set.
    ///   5. `refreshAlternateHistory` — derives off `bundle.workouts`, writes
    ///      alternate-history map + today's-workouts (guarded so empty bundle
    ///      doesn't clobber the local-HK write in step 6).
    ///   6. `pullHealthKitWorkouts` — local-first write of today's HK workouts
    ///      to App Group + upload to /v1/sessions. Returns true if today's
    ///      workout was just observed for the first time.
    ///   7. If step 6 returned true → refetch bundle (the laptop's auto-rebuild
    ///      should have it by now) → re-run alternate history + widget snapshot.
    ///   8. `evaluateGameState` — last; reads StreakState + Achievements which
    ///      depend on DailyLock flags that step 6 may have flipped.
    ///
    /// Reordering any of 4→5→6 will quietly break things. If you need to add a
    /// step, find the right slot using these dependency notes and update this
    /// block.
    /// Force "today" to roll over from the user's perspective. Posts
    /// `.dayDidRollOver` so views that cache date-derived state in @State
    /// (DailyLockChip, AdaptedSessionView, TimelineView …) re-evaluate
    /// from `Date()`, then re-runs the foreground refresh pipeline so the
    /// bundle, HK workouts, and game state reflect the current day. Used
    /// by the manual "Tick day over" button in TransportSettings — the
    /// auto-rollover when the app simply foregrounds across midnight is
    /// already handled by App.swift's scenePhase change.
    func tickDayOver() {
        NotificationCenter.default.post(name: .dayDidRollOver, object: nil)
        Task { await refreshOnForeground() }
    }

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
        refreshAlternateHistory()
        let newWorkoutLanded = await pullHealthKitWorkouts()
        // If today's HK workout was just observed for the first time, the
        // bundle we fetched at the top of this function predates the
        // /v1/sessions upload. Pull a fresh bundle so the workouts list +
        // adaptive engine reflect the cycle/run/etc. this foreground.
        if newWorkoutLanded {
            if let fresh = try? await DataLoader.shared.loadBundle() {
                bundle = fresh
                refreshAlternateHistory()
                if let b = bundle { WidgetSnapshotWriter.update(from: b) }
            }
        }
        evaluateGameState()
    }

    func bootstrap() async {
        // One-shot migration: legacy workout-skip-reason keys → unified
        // Deviation rows (guarded by did_migrate_skip_keys_v1).
        DeviationStore.migrateLegacySkipKeys()

        loading = true
        if #available(iOS 16.2, *) {
            WorkoutLiveActivity.cleanupOrphans()
            // Bring the always-on band Live Activity up. Idempotent: if
            // one is already alive (from a previous session that didn't
            // tear down cleanly), this just refreshes its content with
            // the current band.
            BandLiveActivity.ensureRunning()
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
        refreshAlternateHistory()
        if let cards = bundle?.action_loop {
            let fired = await NotificationManager.shared.diffAndNotify(
                cards: cards, live: liveValues)
            if !fired.isEmpty {
                lastUploadResult = "Notified: \(fired.count) card\(fired.count == 1 ? "" : "s") changed state"
            }
        }
        let newWorkoutLanded = await pullHealthKitWorkouts()
        if newWorkoutLanded {
            if let fresh = try? await DataLoader.shared.loadBundle() {
                bundle = fresh
                refreshAlternateHistory()
                if let b = bundle { WidgetSnapshotWriter.update(from: b) }
            }
        }
        evaluateGameState()
        loading = false
    }

    /// Refresh "what instead" alternate history (last 90d sport counts) AND
    /// the today's-workouts row used by the home-screen chip + the
    /// DeviationSheet's "what instead?" pre-fill.
    private func refreshAlternateHistory() {
        guard let workouts = bundle?.workouts else { return }
        var counts: [String: Int] = [:]
        var today: [DeviationStore.TodayWorkout] = []
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        for w in workouts {
            guard let s = w.sport, !s.isEmpty,
                  let d = iso.date(from: w.ts_start), d > cutoff else { continue }
            let pretty = s.replacingOccurrences(of: "_", with: " ").capitalized
            counts[pretty, default: 0] += 1
            if cal.isDate(d, inSameDayAs: todayStart) {
                let mins = Int(((w.duration_s ?? 0) / 60).rounded())
                today.append(.init(sport: pretty, durationMin: mins, date: todayStart))
            }
        }
        DeviationStore.setAlternateHistory(counts)
        // Only overwrite today's-workouts if the bundle actually has rows
        // for today. Otherwise leave whatever `pullHealthKitWorkouts` just
        // wrote from local HK in place — the bundle may be stale (laptop
        // offline, refresh.sh not yet run) and clobbering would make the
        // home-screen chip flicker off.
        if !today.isEmpty {
            DeviationStore.setTodayWorkouts(today)
        }
    }

    func refreshLive() async {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let rhr    = HealthStore.shared.latest(.restingHeartRate, unit: bpm, hours: 48)
        async let vo2    = HealthStore.shared.latest(.vo2Max,
                              unit: HKUnit(from: "ml/(kg*min)"), hours: 24 * 60)
        async let weight = HealthStore.shared.latest(.bodyMass,
                              unit: .pound(), hours: 24 * 30)
        async let sysBP  = HealthStore.shared.latest(.bloodPressureSystolic,
                              unit: .millimeterOfMercury(), hours: 24 * 60)
        async let diaBP  = HealthStore.shared.latest(.bloodPressureDiastolic,
                              unit: .millimeterOfMercury(), hours: 24 * 60)
        async let sleep  = HealthStore.shared.sleepMinutes(hours: 36)

        let (rhrV, vo2V, weightV, sysBPV, diaBPV, sleepV) =
            await (rhr, vo2, weight, sysBP, diaBP, sleep)

        var v: [String: Double] = [:]
        if let rhrV    { v["heart_rate_resting"] = rhrV }
        if let vo2V    { v["vo2max"]             = vo2V }
        if let weightV { v["weight"]             = weightV }
        if let sysBPV  { v["bp_systolic"]        = sysBPV }
        if let diaBPV  { v["bp_diastolic"]       = diaBPV }
        if let sleepV  { v["sleep_minutes"]      = sleepV }
        liveValues = v
    }
}
