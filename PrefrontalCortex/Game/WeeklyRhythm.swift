import Foundation

/// User-defined weekly cadence. Each day of the week carries a `kind`
/// (rest / gym / run / mobility / improv / travel / recovery / …) and
/// an optional freeform `anchor` like "improv 8pm" — the laptop
/// pipeline reads this on its next refresh and uses it to shape the
/// daily_protocol map.
///
/// Stored at `iCloud config/weekly_rhythm.json`. Renders on the Plan
/// tab via WeeklyRhythmCard; edited via WeeklyRhythmEditorSheet.
struct WeeklyRhythm: Codable, Equatable {
    /// Stable ordered day keys. Match what the pipeline expects on the
    /// Python side. Don't reorder.
    static let dayKeys: [String] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// Display label for a day key — used in the editor sheet rows.
    static func dayLabel(_ key: String) -> String {
        switch key {
        case "mon": return "Monday"
        case "tue": return "Tuesday"
        case "wed": return "Wednesday"
        case "thu": return "Thursday"
        case "fri": return "Friday"
        case "sat": return "Saturday"
        case "sun": return "Sunday"
        default:    return key.capitalized
        }
    }

    /// One day's configuration. Both fields are persisted; both are
    /// editable inline.
    struct DayConfig: Codable, Equatable, Hashable {
        var kind: String        // free-form — see `kindPresets` for the suggested set
        var anchor: String?     // free-form — "improv 8pm" / "travel — Tokyo" / etc.

        init(kind: String, anchor: String? = nil) {
            self.kind = kind
            self.anchor = anchor
        }
    }

    /// Map day-key → config. Use a dictionary (not seven separate
    /// stored properties) so adding a "missed days override" or
    /// per-week schedule later doesn't require a Codable migration.
    var days: [String: DayConfig]

    /// Suggested kinds rendered in the editor's picker. The set is a
    /// suggestion only — the user can type any string and the pipeline
    /// is responsible for normalising / treating unknown kinds.
    static let kindPresets: [String] = [
        "rest", "recovery", "mobility",
        "gym", "light_gym",
        "run", "light_run",
        "improv", "travel"
    ]

    /// Empty-as-baseline rhythm — every day defaults to "gym". The user
    /// edits from here. This is what readConfig returns nil for on a
    /// fresh install.
    static func empty() -> WeeklyRhythm {
        var d: [String: DayConfig] = [:]
        for k in dayKeys { d[k] = DayConfig(kind: "gym") }
        return WeeklyRhythm(days: d)
    }

    /// Convenience access — returns the day's config, falling back to
    /// the "gym" default so callers never have to nil-check.
    func config(for key: String) -> DayConfig {
        days[key] ?? DayConfig(kind: "gym")
    }
}

/// Read/write wrapper around iCloudTransport. The store fires
/// `weeklyRhythmDidChange` on every successful save so the Plan-tab
/// card refreshes without a manual reload.
enum WeeklyRhythmStore {
    static func load() async -> WeeklyRhythm {
        // `try?` of a throwing function that returns `T?` flattens to `T?`
        // under Swift 5+, so a single `if let` is the right unwrap here —
        // a second shorthand `let r` would fail because r is already
        // non-optional after the first binding.
        if let r = try? await iCloudTransport.shared
            .readConfig(name: "weekly_rhythm", as: WeeklyRhythm.self) {
            return r
        }
        return WeeklyRhythm.empty()
    }

    static func save(_ rhythm: WeeklyRhythm) async throws {
        try await iCloudTransport.shared.writeConfig(name: "weekly_rhythm", rhythm)
        await MainActor.run {
            NotificationCenter.default.post(name: .weeklyRhythmDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let weeklyRhythmDidChange = Notification.Name("PrefrontalCortex.weeklyRhythmDidChange")
}
