import SwiftUI

@main
struct PrefrontalCortexApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var bandEdgeTimer: Timer?
    // Separate from bandEdgeTimer. Band edges land at 6/12/17/19/22 and
    // 06 next-day — none at 00:00 — so the night band straddles midnight.
    // Without a dedicated midnight tick, an app left open across midnight
    // would keep rendering yesterday's program_day in date-derived views
    // until the 6am band edge finally fired.
    @State private var dayRolloverTimer: Timer?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    await store.bootstrap()
                    scheduleNextBandEdge()
                    scheduleNextMidnight()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Broadcast the rollover so date-derived views
                        // (DailyLockChip, AdaptedSessionView, TimelineView,
                        // PresentFocusCard) re-evaluate from `Date()` on
                        // foreground — covers the "app left open across
                        // midnight" case where .onAppear doesn't re-fire.
                        NotificationCenter.default.post(name: .dayDidRollOver, object: nil)
                        // .calendarDayChanged is the stricter "actual day
                        // crossed" signal — only fire it when the calendar
                        // date is new since the last foreground. Without
                        // this guard, once-per-day handlers (DayCloseView
                        // rollover overlay) trigger on every foreground.
                        PrefrontalCortexApp.postCalendarDayChangedIfNeeded()
                        Task { @MainActor in NotificationManager.shared.syncWorkoutNudge() }
                        // Always-on band Live Activity: refresh content to
                        // the current band on every foreground (covers
                        // backgrounded-across-an-edge), making sure one is
                        // running if iOS killed it.
                        if #available(iOS 16.2, *) {
                            BandLiveActivity.ensureRunning()
                        }
                        if store.bundle != nil {
                            Task { await store.refreshOnForeground() }
                        }
                        // The timer is invalidated by iOS during background;
                        // re-arm it for the next band edge now that we're
                        // foregrounded again.
                        scheduleNextBandEdge()
                        scheduleNextMidnight()
                    } else if newPhase == .background {
                        bandEdgeTimer?.invalidate()
                        bandEdgeTimer = nil
                        dayRolloverTimer?.invalidate()
                        dayRolloverTimer = nil
                    }
                }
        }
    }

    /// Force a calendar-day rollover at 00:00 local. Independent of the
    /// band-edge timer because TimeBand.nextEdge doesn't put an edge at
    /// midnight (the "night" band is 22 → 06 next-day in one stretch).
    /// Posts .dayDidRollOver so NowFocusView re-derives todayKey, then
    /// re-arms for the next midnight. Live Activity gets re-instantiated
    /// here too so the lock screen flips to the new day's content even
    /// when the app stays foregrounded.
    private func scheduleNextMidnight() {
        dayRolloverTimer?.invalidate()
        var cal = Calendar.current
        cal.timeZone = .current
        // +1s past midnight so Date() definitely lands on the new day
        // when the closure reads it (avoids "fires at 23:59:59.9").
        guard let next = cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 1),
            matchingPolicy: .nextTime
        ) else { return }
        let t = Timer(fire: next, interval: 0, repeats: false) { _ in
            NotificationCenter.default.post(name: .dayDidRollOver, object: nil)
            // Midnight always means the calendar day actually changed —
            // stamp the new date and post the stricter signal so the
            // DayCloseView overlay opens here (and only here, alongside
            // the scenePhase.active guard above for the
            // backgrounded-across-midnight case).
            PrefrontalCortexApp.postCalendarDayChangedIfNeeded()
            if #available(iOS 16.2, *) {
                BandLiveActivity.ensureRunning()
            }
            DispatchQueue.main.async { scheduleNextMidnight() }
        }
        RunLoop.main.add(t, forMode: .common)
        dayRolloverTimer = t
    }

    /// UserDefaults key for the last calendar date we posted
    /// `.calendarDayChanged` for. Stored as a `yyyy-MM-dd` string in the
    /// app's default suite so it survives backgrounding + relaunch but
    /// is intentionally NOT shared with the widget app group (the
    /// rollover overlay is foreground-only).
    private static let _lastCalDateKey = "PrefrontalCortex.lastCalendarDay"

    /// Post `.calendarDayChanged` iff today's date differs from the
    /// last date we stamped. Idempotent — calling it many times within
    /// the same day fires the notification at most once. Used by both
    /// the midnight timer (always a new day) and scenePhase.active
    /// (only a new day after backgrounding across midnight).
    fileprivate static func postCalendarDayChangedIfNeeded() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let last = UserDefaults.standard.string(forKey: _lastCalDateKey)
        guard last != today else { return }
        UserDefaults.standard.set(today, forKey: _lastCalDateKey)
        // Don't fire on the very first run after install — there's no
        // "previous day" to close. The stamp gets written either way so
        // subsequent runs gate correctly.
        guard last != nil else { return }
        NotificationCenter.default.post(name: .calendarDayChanged, object: nil)
    }

    /// Arm a single-shot Timer that fires precisely at the next TimeBand
    /// edge (6, 12, 17, 19, 22, or 06 next-day). When it fires we post
    /// `.dayDidRollOver` so PresentFocusCard + DailyLockChip re-read
    /// `TimeBand.current()` and `Date()` without needing user interaction,
    /// then re-arm for the following edge. This is what makes "the day
    /// ticks over 100%" — even with the app continuously open.
    private func scheduleNextBandEdge() {
        bandEdgeTimer?.invalidate()
        let next = TimeBand.nextEdge(after: Date())
        let interval = next.timeIntervalSinceNow
        guard interval > 0 else {
            // Already past — fire immediately and re-schedule.
            NotificationCenter.default.post(name: .dayDidRollOver, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { scheduleNextBandEdge() }
            return
        }
        let t = Timer(fire: next, interval: 0, repeats: false) { _ in
            NotificationCenter.default.post(name: .dayDidRollOver, object: nil)
            DispatchQueue.main.async { NotificationManager.shared.syncWorkoutNudge() }
            // Always-on band Live Activity update at the edge — the iOS
            // lock screen / Dynamic Island flip to the new band's headline
            // even when the app stays foregrounded. Use ensureRunning (not
            // bare refresh) so a band edge ALSO re-instantiates the
            // activity if iOS ended it past the 8-hour ActivityKit limit
            // while the app was foregrounded; refresh() alone would no-op
            // and the lock screen would stay empty until next foreground.
            if #available(iOS 16.2, *) {
                BandLiveActivity.ensureRunning()
            }
            // Re-arm for the band after this one. Hop to main since Timer
            // closures aren't @MainActor-isolated by default.
            DispatchQueue.main.async { scheduleNextBandEdge() }
        }
        RunLoop.main.add(t, forMode: .common)
        bandEdgeTimer = t
    }
}
