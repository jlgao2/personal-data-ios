import ActivityKit
import Foundation

/// ActivityKit attributes for the always-on band indicator.
///
/// Different from `WorkoutLiveActivityAttributes` — that one tracks the
/// in-progress workout state and only exists while a workout is open.
/// This one runs continuously, surfacing the current TimeBand's headline
/// on the lock screen + Dynamic Island. When a workout starts the band
/// activity ends (handover to WorkoutLiveActivity); when the workout
/// ends the band activity restarts.
///
/// `bandRaw` is the `TimeBand` raw value (string) so the widget process
/// can re-instantiate the enum without linking the host's Game module.
struct BandLiveActivityAttributes: ActivityAttributes {

    /// Wall-clock when this activity instance was requested. Bands rotate
    /// in place via content updates rather than starting a fresh activity
    /// per band, so this can sit static. Useful for orphan cleanup.
    let startedAt: Date

    /// Strict subset of TimeBand. Decoupled from the enum so the widget
    /// extension doesn't have to link the host's Game module — band rules
    /// live in the host and shape the content state we ship.
    struct ContentState: Codable, Hashable {
        /// TimeBand.rawValue — "morning" | "midday" | "workout" | "reachOut" | "night".
        var bandRaw: String
        /// Short uppercased label rendered as the leading pill.
        var tag: String
        /// Headline imperative — "Eat mindfully.", "Train.", etc.
        var headline: String
        /// One-line subtitle below the headline.
        var subtitle: String
        /// SF Symbol name shown on the trailing edge.
        var symbol: String
        /// Hex-ish color hint for the accent ("orange", "yellow", "cyan", ...).
        /// Decoded by the widget into a real SwiftUI Color.
        var accent: String
    }
}
