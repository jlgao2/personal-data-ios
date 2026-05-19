import SwiftUI

@main
struct PrefrontalCortexApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var bandEdgeTimer: Timer?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    await store.bootstrap()
                    scheduleNextBandEdge()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Broadcast the rollover so date-derived views
                        // (DailyLockChip, AdaptedSessionView, TimelineView,
                        // PresentFocusCard) re-evaluate from `Date()` on
                        // foreground — covers the "app left open across
                        // midnight" case where .onAppear doesn't re-fire.
                        NotificationCenter.default.post(name: .dayDidRollOver, object: nil)
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
                    } else if newPhase == .background {
                        bandEdgeTimer?.invalidate()
                        bandEdgeTimer = nil
                    }
                }
        }
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
            // even when the app stays foregrounded.
            if #available(iOS 16.2, *) {
                Task { await BandLiveActivity.refresh() }
            }
            // Re-arm for the band after this one. Hop to main since Timer
            // closures aren't @MainActor-isolated by default.
            DispatchQueue.main.async { scheduleNextBandEdge() }
        }
        RunLoop.main.add(t, forMode: .common)
        bandEdgeTimer = t
    }
}
