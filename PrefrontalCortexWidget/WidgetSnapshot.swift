import Foundation

/// The slim shape both the main app and the widget agree on.
/// Main app writes this to the App Group container after each refresh;
/// widget reads it on every timeline tick.
struct WidgetSnapshot: Codable {
    let updated_at: String
    let hero_eyebrow: String       // "Most off-target · ACTN3" or "All clear · today's focus"
    let hero_sentence: String      // single italic sentence
    let hero_state: String         // "ok" | "drift" | "warn"
    let traffic_light: String      // "green" | "amber" | "red"
    let intensity_pct: Int         // 0-100
    let session_label: String      // e.g. "Pull + Lower + core"
    let stack_done: Int            // taken today
    let stack_total: Int           // all entries
    let reach_out_top_name: String?
    let reach_out_top_attn: Int?
    let reach_out_top_days: Int?
    /// Upcoming items today, sorted ascending by time. The NextUpWidget
    /// builds a multi-entry timeline from this so it auto-advances through
    /// each as time passes — no need for fresh snapshots.
    let next_up: [NextUpItem]?
    let streak_current: Int?
    let streak_longest: Int?
}

/// One thing on today's chronological list. `time_iso` is full ISO so the
/// widget can construct a Date and decide whether it's still in the future.
struct NextUpItem: Codable, Identifiable {
    let time_iso: String
    let title: String
    let kind: String   // "calendar" | "supps_morning" | "supps_evening" | "workout" | "reach_out"

    var id: String { time_iso + title }

    var symbol: String {
        switch kind {
        case "calendar":       return "calendar"
        case "supps_morning":  return "sunrise"
        case "supps_evening":  return "moon.stars"
        case "workout":        return "figure.run"
        case "reach_out":      return "person.wave.2"
        default:               return "circle"
        }
    }
}

enum WidgetSnapshotIO {
    static let appGroup = "group.com.jlgao.PrefrontalCortex"
    static let filename = "widget_snapshot.json"

    static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snap: WidgetSnapshot) {
        guard let url else { return }
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
