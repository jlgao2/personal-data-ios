import Foundation
import WidgetKit

/// After every bundle refresh, the main app derives the slim widget
/// snapshot and writes it to the App Group container so the widget
/// extension can read it.
struct WidgetSnapshotWriter {

    static func update(from bundle: IOSBundle, stackDoneToday: Int = 0) {
        let snap = derive(bundle: bundle, stackDoneToday: stackDoneToday)
        write(snap)
        // Tell WidgetKit to refresh.
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func derive(bundle: IOSBundle, stackDoneToday: Int) -> WidgetSnapshotShape {
        let stateRank = ["off": 0, "drift": 1, "ok": 2, "none": 3]
        let scored: [(card: ActionCard, state: String)] = bundle.action_loop.map { c in
            let s = computeCardStateForWidget(actual: c.latest_value,
                                              target: c.target_value,
                                              direction: c.expected_direction)
            return (c, s)
        }
        let sorted = scored.sorted { (stateRank[$0.state] ?? 99) < (stateRank[$1.state] ?? 99) }
        let worst = sorted.first

        let adapted = bundle.adapted_session
        let trafficLight = adapted?.traffic_light ?? "green"
        let intensity = Int(((adapted?.intensity_modifier ?? 1.0) * 100).rounded())
        let sessionLabel = adapted?.prescribed ?? "—"

        let eyebrow: String
        let sentence: String
        let heroState: String

        if let w = worst, w.state != "ok", w.state != "none" {
            let label = w.card.sample_type.replacingOccurrences(of: "_", with: " ")
            let actual = w.card.latest_value.map { String(format: "%.1f", $0) } ?? "—"
            let target = w.card.target_value.map { String(format: "%g", $0) } ?? "?"
            let verb = w.card.expected_direction == "increase" ? "<" : "≥"
            eyebrow = "Most off-target · \(w.card.gene ?? "PRS")"
            sentence = "\(label.capitalized) \(actual) (target \(verb) \(target))."
            heroState = w.state == "off" ? "warn" : "drift"
        } else {
            eyebrow = "All clear · today's focus"
            sentence = sessionLabel
            heroState = "ok"
        }

        let firstReach = bundle.social?.reach_out?.first
        let stackTotal = bundle.profile?.supplement_stack?.count ?? 0
        let streak = StreakState.load()

        return WidgetSnapshotShape(
            updated_at: bundle.exported_at,
            hero_eyebrow: eyebrow,
            hero_sentence: sentence,
            hero_state: heroState,
            traffic_light: trafficLight,
            intensity_pct: intensity,
            session_label: sessionLabel,
            stack_done: stackDoneToday,
            stack_total: stackTotal,
            reach_out_top_name: firstReach?.name,
            reach_out_top_attn: firstReach?.attention_score,
            reach_out_top_days: firstReach?.days_since_last,
            next_up: computeNextUp(bundle: bundle),
            streak_current: streak.current,
            streak_longest: streak.longest
        )
    }

    /// Build today's upcoming list — calendar events + morning/evening supps
    /// + workout anchor + reach-out — sorted ascending by time. The widget's
    /// timeline provider builds a multi-entry timeline so it auto-advances
    /// through these as time passes (no need for new snapshots).
    static func computeNextUp(bundle: IOSBundle) -> [WidgetNextUpItem] {
        var items: [WidgetNextUpItem] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: today) else { return [] }
        let isoIn  = ISO8601DateFormatter()
        isoIn.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoAlt = ISO8601DateFormatter()
        let isoOut = ISO8601DateFormatter()

        // Calendar
        for e in bundle.calendar ?? [] {
            guard let s = e.start,
                  let date = isoIn.date(from: s) ?? isoAlt.date(from: s) else { continue }
            if date < today || date >= todayEnd { continue }
            items.append(.init(
                time_iso: isoOut.string(from: date),
                title: e.summary ?? "(event)",
                kind: "calendar"
            ))
        }

        let supps = bundle.profile?.supplement_stack ?? []
        let hasMorning = supps.contains { s in
            let t = (s.timing ?? "").lowercased()
            return !t.contains("evening") && !t.contains("before bed") && !t.contains("night")
        }
        let hasEvening = supps.contains { s in
            let t = (s.timing ?? "").lowercased()
            return t.contains("evening") || t.contains("before bed") || t.contains("night")
        }
        if hasMorning, let t = anchorTime(at: 8, in: today, cal: cal) {
            items.append(.init(time_iso: isoOut.string(from: t),
                               title: "Morning supps", kind: "supps_morning"))
        }
        if hasEvening, let t = anchorTime(at: 19, in: today, cal: cal) {
            items.append(.init(time_iso: isoOut.string(from: t),
                               title: "Evening supps", kind: "supps_evening"))
        }

        // Workout anchor (11am for non-rest days)
        let dayKey = todaysProgramKey()
        if dayKey != "Day 7", let day = bundle.profile?.daily_protocol?[dayKey],
           let t = anchorTime(at: 11, in: today, cal: cal) {
            items.append(.init(time_iso: isoOut.string(from: t),
                               title: day.session, kind: "workout"))
        }

        // Reach out (8pm)
        if let top = bundle.social?.reach_out?.first,
           let t = anchorTime(at: 20, in: today, cal: cal) {
            items.append(.init(time_iso: isoOut.string(from: t),
                               title: "Reach out: \(top.name ?? "Friend")",
                               kind: "reach_out"))
        }

        return items.sorted { $0.time_iso < $1.time_iso }
    }

    private static func anchorTime(at hour: Int, in dayStart: Date, cal: Calendar) -> Date? {
        var c = cal.dateComponents([.year, .month, .day], from: dayStart)
        c.hour = hour
        return cal.date(from: c)
    }

    private static func todaysProgramKey() -> String {
        let dow = Calendar.current.component(.weekday, from: Date())
        let mondayBased = ((dow + 5) % 7) + 1
        return "Day \(mondayBased)"
    }

    static func write(_ snap: WidgetSnapshotShape) {
        guard let url = appGroupURL() else { return }
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func appGroupURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.jlgao.PrefrontalCortex")?
            .appendingPathComponent("widget_snapshot.json")
    }
}

private func computeCardStateForWidget(actual: Double?, target: Double?, direction: String?) -> String {
    guard let actual, let target, target != 0 else { return "none" }
    let ratio = actual / target
    let dir = direction ?? "increase"
    if dir == "increase" {
        if ratio < 0.95 { return "ok" }
        if ratio < 1.10 { return "drift" }
        return "off"
    }
    if ratio >= 1.0 { return "ok" }
    if ratio >= 0.85 { return "drift" }
    return "off"
}

/// Mirror of WidgetSnapshot — duplicated here because the widget extension
/// is a separate target and we don't share Codable structs across target
/// boundaries via a framework yet. The shape MUST match.
struct WidgetSnapshotShape: Codable {
    let updated_at: String
    let hero_eyebrow: String
    let hero_sentence: String
    let hero_state: String
    let traffic_light: String
    let intensity_pct: Int
    let session_label: String
    let stack_done: Int
    let stack_total: Int
    let reach_out_top_name: String?
    let reach_out_top_attn: Int?
    let reach_out_top_days: Int?
    let next_up: [WidgetNextUpItem]?
    let streak_current: Int?
    let streak_longest: Int?
}

/// Mirror of NextUpItem — duplicated across the target boundary.
struct WidgetNextUpItem: Codable {
    let time_iso: String
    let title: String
    let kind: String
}
