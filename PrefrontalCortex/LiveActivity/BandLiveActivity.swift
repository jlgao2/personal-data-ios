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
        let band = TimeBand.current()
        let state = contentState(for: band)
        let attrs = BandLiveActivityAttributes(startedAt: Date())
        do {
            _ = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: TimeBand.nextEdge()),
                pushType: nil
            )
        } catch {
            print("BandLiveActivity.ensureRunning failed: \(error)")
        }
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
        BandLiveActivityAttributes.ContentState(
            bandRaw: band.rawValue,
            tag: band.tag,
            headline: band.headline,
            subtitle: band.subtitle,
            symbol: band.symbol,
            accent: band.accentName
        )
    }
}
