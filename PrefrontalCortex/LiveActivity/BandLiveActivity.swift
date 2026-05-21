import ActivityKit
import Foundation
import WidgetKit

/// Static facade for the always-on band Live Activity. Mirrors the shape
/// of `WorkoutLiveActivity` but runs continuously rather than only during
/// workouts.
///
/// Lifecycle:
///   * `ensureRunning()` — called on app bootstrap + scenePhase active.
///     Starts the activity if not already alive; refreshes content if
///     alive but stale.
///   * Listens to `.dayDidRollOver` → `refresh()`. Band edge crossings
///     re-publish the activity's ContentState so the lock screen / DI
///     reflect the new band.
///   * Workout takeover: `WorkoutLiveActivity.start` calls `endAll()`
///     before requesting its own activity, and `endAll(immediate:)` on
///     the workout activity calls `ensureRunning()` to bring the band
///     activity back. Two activities at once would clutter the lock
///     screen; we maintain a single-activity invariant across both
///     attribute types.
///
/// Stale-date strategy: each content update sets `staleDate` to the
/// next `TimeBand.nextEdge`. iOS visually dims the activity past that
/// point if the app hasn't refreshed it in the meantime — fine because
/// the foreground / scenePhase path re-arms within a second of next
/// activation.
@available(iOS 16.2, *)
enum BandLiveActivity {

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var isAuthorized: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Make sure the band activity is running with current content.
    /// Idempotent — refreshes in place if alive, starts otherwise.
    static func ensureRunning() {
        guard isAuthorized else { return }
        if Activity<BandLiveActivityAttributes>.activities.first != nil {
            Task { await refresh() }
            return
        }
        // Wire the .dayDidRollOver observer the first time we start one.
        // The doc comment up top has always claimed "Listens to
        // .dayDidRollOver → refresh()" but the subscriber never existed —
        // App.swift's midnight + band-edge timers are the actual callers.
        // This adds belt-and-braces so any future poster of .dayDidRollOver
        // (a manual "tick over" button, a background fetch) also keeps
        // the activity alive.
        installDayRolloverObserverOnce()
        let band = TimeBand.current()
        let state = contentState(for: band)
        let attrs = BandLiveActivityAttributes(startedAt: Date())
        do {
            // pushType: nil → the activity lives within the 8h-active +
            // 4h-stale ActivityKit ceiling for non-push activities. App
            // foreground / band-edge / midnight timers re-instantiate
            // after iOS ends it. For true always-on (no ceiling), we'd
            // need pushType: .token + an APNs backend; see the comment at
            // capturePushTokenIfAvailable() below for the gap.
            let activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: TimeBand.nextEdge()),
                pushType: nil
            )
            capturePushTokenIfAvailable(activity)
        } catch {
            print("BandLiveActivity.ensureRunning failed: \(error)")
        }
    }

    private static var dayRolloverObserverInstalled = false
    private static func installDayRolloverObserverOnce() {
        guard !dayRolloverObserverInstalled else { return }
        dayRolloverObserverInstalled = true
        NotificationCenter.default.addObserver(
            forName: .dayDidRollOver,
            object: nil,
            queue: .main
        ) { _ in
            if #available(iOS 16.2, *) { ensureRunning() }
        }
    }

    /// No-op until the app gains an APNs path. Today we request the
    /// activity with `pushType: nil`, which means ActivityKit doesn't
    /// hand us a push token at all — but the moment we flip pushType
    /// to `.token` (which itself requires the `aps-environment`
    /// entitlement + Push Notifications capability on the App ID in
    /// Apple Developer + an APNs auth key + a server that sends the
    /// updates), this is where the token capture would live:
    ///
    ///   Task {
    ///       for await tokenData in activity.pushTokenUpdates {
    ///           let hex = tokenData.map { String(format: "%02hhx", $0) }
    ///               .joined()
    ///           // POST hex to your APNs sender so it can push activity
    ///           // ContentState updates on a cadence the laptop pipeline
    ///           // controls, bypassing the 8h ActivityKit ceiling.
    ///       }
    ///   }
    ///
    /// Left as a stub so the call site stays honest about the gap —
    /// the local-only timers won't make the activity perpetual; only
    /// push can.
    private static func capturePushTokenIfAvailable(_ activity: Activity<BandLiveActivityAttributes>) {
        // Intentionally empty until APNs is wired (see above).
    }

    /// Push fresh content (current band) to every alive band activity.
    /// Cheap to call repeatedly — invoked from the band-edge timer +
    /// .dayDidRollOver subscribers.
    static func refresh() async {
        let band = TimeBand.current()
        let state = contentState(for: band)
        let stale = TimeBand.nextEdge()
        for activity in Activity<BandLiveActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: stale))
        }
    }

    /// End every band activity. Called by `WorkoutLiveActivity.start`
    /// so the lock screen doesn't show two stacked activities during
    /// a workout.
    static func endAll() async {
        for activity in Activity<BandLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Cleanup pass run from `AppStore.bootstrap`. Bands rotate in place,
    /// so the activity's `startedAt` can be days old without it being an
    /// orphan — we instead key on whether the content is current. Just
    /// refresh; no force-end.
    static func cleanupAndRefresh() {
        Task { await refresh() }
    }

    private static func contentState(for band: TimeBand) -> BandLiveActivityAttributes.ContentState {
        // The workout band's static headline is "Train." — but the Now
        // card shows the actual session ("Rest day", "Push + core",
        // "Did: Cycling · 190 min"). Read the widget snapshot the app
        // writes after every bundle refresh so the lock screen matches
        // the card instead of always saying "Train".
        var headline = band.headline
        if band == .workout, let label = workoutSessionLabel() {
            headline = label
        }
        return BandLiveActivityAttributes.ContentState(
            bandRaw: band.rawValue,
            tag: band.tag,
            headline: headline,
            subtitle: band.subtitle,
            symbol: band.symbol,
            accent: band.accentName
        )
    }

    /// Latest session label from the App Group widget snapshot, or nil
    /// if it's missing / placeholder (fall back to the band headline).
    private static func workoutSessionLabel() -> String? {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appendingPathComponent("widget_snapshot.json"),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(WidgetSnapshotShape.self, from: data)
        else { return nil }
        let s = snap.session_label.trimmingCharacters(in: .whitespaces)
        return (s.isEmpty || s == "—") ? nil : s
    }
}
