import SwiftUI

/// Plan & Vision tab content.
/// Action Loop sits between Goals and Roadmap because it's the same shape
/// (target vs measured) — genome-derived targets next to user-set goals.
struct PlanTabView: View {
    let profile: HealthProfile
    let vitals: [String: VitalSeries]
    let workouts: [Workout]
    let actionLoop: [ActionCard]
    let live: [String: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let vision = profile.vision_statement {
                VisionView(text: vision)
            }
            if let goals = profile.goals, !goals.isEmpty {
                GoalsView(goals: goals)
            }
            // First interactive surface on the Plan tab — tap to edit
            // the weekly cadence. Writes config/weekly_rhythm.json to
            // iCloud; the laptop pipeline picks it up on next refresh.
            WeeklyRhythmCard()
            ActionLoopView(cards: actionLoop, live: live)
            RoadmapView(profile: profile)
            StreakView(vitals: vitals, workouts: workouts)
        }
    }
}

// MARK: - Vision

struct VisionView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VISION")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            Text(text)
                .font(.title3.italic())
                .foregroundStyle(.white)
                .lineSpacing(4)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.cyan).frame(width: 2)
                }
        }
    }
}

// MARK: - Goals

struct GoalsView: View {
    let goals: [Goal]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GOALS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                Text("\(goals.count) targets")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 1) {
                ForEach(goals) { g in GoalRow(goal: g) }
            }
            .background(Color.white.opacity(0.05))
        }
    }
}

private struct GoalRow: View {
    let goal: Goal
    @ObservedObject private var calStore = CalendarStore.shared
    @State private var added: Bool = false
    @State private var addedError: String? = nil

    private var pct: Double {
        guard let baseline = goal.baseline,
              let current = goal.current,
              let target = goal.target,
              target != baseline else { return 0 }
        let total = target - baseline
        let done  = current - baseline
        return max(0, min(100, (done / total) * 100))
    }

    private var isPending: Bool {
        goal.current == nil || goal.baseline == nil || goal.target == nil
    }

    private var state: String {
        if isPending { return "pending" }
        // Naive linear schedule check from May 1 → deadline
        guard let dlString = goal.deadline,
              let dl = ISO8601DateFormatter().date(from: dlString + "T00:00:00Z") else {
            return "pending"
        }
        let start = Date(timeIntervalSince1970: 1777_982_400) // 2026-05-05 approx
        let now = Date()
        let total = dl.timeIntervalSince(start)
        guard total > 0 else { return "pending" }
        let elapsed = now.timeIntervalSince(start) / total
        let expectedPct = elapsed * 100
        if pct >= expectedPct { return "ahead" }
        if pct < expectedPct - 15 { return "behind" }
        return "pending"
    }

    private var stateColor: Color {
        switch state {
        case "ahead":   return .green
        case "behind":  return .red
        default:        return .cyan
        }
    }

    private var deadlineFormatted: String {
        guard let s = goal.deadline else { return "—" }
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: s + "T00:00:00Z") else { return s }
        let df = DateFormatter()
        df.dateFormat = "MMM yy"
        return df.string(from: d)
    }

    private var pathSummary: String {
        let cur = goal.current.map { String(format: "%g", $0) } ?? "—"
        let tgt = goal.target.map  { String(format: "%g", $0) } ?? "—"
        return "\(cur) → \(tgt) \(goal.units ?? "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.name)
                    .font(.body.italic())
                    .foregroundStyle(.white)
                Spacer()
                Text(deadlineFormatted)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(pathSummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if let cat = goal.category {
                    Text(cat.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(stateColor)
                }
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Rectangle().fill(stateColor)
                        .frame(width: geo.size.width * CGFloat(pct / 100), height: 4)
                }
            }
            .frame(height: 4)
            if let n = goal.note {
                Text(n)
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            // Calendar action: create a check-in event 7 days before the deadline.
            if calStore.authorized, goal.deadline != nil, !added {
                Button(action: { Task { await addReminder() } }) {
                    Text("+ ADD REMINDER")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                        .tracking(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.cyan, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            if added {
                Text("✓ ADDED TO CALENDAR")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.green)
                    .tracking(2)
                    .padding(.top, 4)
            }
            if let e = addedError {
                Text(e)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }

    private func addReminder() async {
        guard let dlString = goal.deadline else { return }
        let f = ISO8601DateFormatter()
        guard let dl = f.date(from: dlString + "T09:00:00Z") else { return }
        let remindAt = dl.addingTimeInterval(-7 * 86_400)
        let title = "Goal check-in: \(goal.name)"
        let notes = goal.note ?? ""
        let ok = await calStore.createEvent(title: title, date: remindAt,
                                            duration: 30 * 60, notes: notes)
        if ok { added = true } else { addedError = calStore.lastError }
    }
}

// MARK: - Roadmap

struct RoadmapView: View {
    let profile: HealthProfile

    private var blocks: [(tick: String, title: String, items: [String])] {
        [
            ("0",     "Now · this week",  profile.action_plan_immediate ?? []),
            ("4-8w",  "Block 2 · 4-8w",   profile.action_plan_short_term_4_to_8_weeks ?? []),
            ("2-3mo", "Block 3 · 2-3mo",  profile.action_plan_medium_term_2_to_3_months ?? []),
            ("∞",     "Ongoing",          profile.action_plan_ongoing ?? []),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ROADMAP")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            VStack(spacing: 1) {
                ForEach(blocks, id: \.tick) { b in
                    RoadmapBlock(tick: b.tick, title: b.title, items: b.items)
                }
            }
            .background(Color.white.opacity(0.05))
        }
    }
}

private struct RoadmapBlock: View {
    let tick: String
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tick.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Text(title.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
            }
            if items.isEmpty {
                Text("—")
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.footnote.italic())
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }
}

// MARK: - Streak

struct StreakView: View {
    let vitals: [String: VitalSeries]
    let workouts: [Workout]

    private static let days = 84   // 12 weeks

    private var sleepStates: [String] { computeSleepStates() }
    private var workoutStates: [String] { computeWorkoutStates() }

    private func dateKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    private func dateRange() -> [Date] {
        let now = Date()
        return (0..<Self.days).map { i -> Date in
            now.addingTimeInterval(TimeInterval(-(Self.days - 1 - i) * 86_400))
        }
    }

    private func computeSleepStates() -> [String] {
        let series = vitals["sleep_minutes"]?.series ?? []
        let map = Dictionary(uniqueKeysWithValues: series.map { ($0.date, $0.value) })
        return dateRange().map { d in
            let v = map[dateKey(d)]
            if v == nil { return "future" }
            if v! >= 420 { return "hit" }
            if v! >= 360 { return "partial" }
            return "miss"
        }
    }

    private func computeWorkoutStates() -> [String] {
        let workoutDays = Set(workouts.compactMap { String($0.ts_start.prefix(10)) })
        return dateRange().map { d in
            let dayNum = ((Calendar.current.component(.weekday, from: d) + 5) % 7) + 1
            if dayNum == 7 { return "hit" }   // Sunday rest = expected
            return workoutDays.contains(dateKey(d)) ? "hit" : "miss"
        }
    }

    private func cellColor(_ state: String) -> Color {
        switch state {
        case "hit":     return .green
        case "partial": return .cyan.opacity(0.7)
        case "miss":    return .red.opacity(0.5)
        default:        return Color.white.opacity(0.06)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STREAK · 12 WEEKS")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            VStack(alignment: .leading, spacing: 8) {
                StreakRow(label: "Sleep ≥7h", states: sleepStates, colorFor: cellColor)
                StreakRow(label: "Workout",   states: workoutStates, colorFor: cellColor)
                HStack(spacing: 12) {
                    LegendItem(color: .green, label: "hit")
                    LegendItem(color: .cyan.opacity(0.7), label: "partial")
                    LegendItem(color: .red.opacity(0.5), label: "miss")
                }
                .padding(.top, 6)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.4))
        }
    }
}

private struct StreakRow: View {
    let label: String
    let states: [String]
    let colorFor: (String) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(1.5)
            // 84 cells in one row would overflow when each one demands its
            // intrinsic aspect-ratio'd width — instead let the HStack share
            // the available width equally and pin a fixed row height. No
            // aspect-ratio enforcement; cells just inherit equal flex slots.
            HStack(spacing: 2) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, s in
                    Rectangle().fill(colorFor(s))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 8, idealHeight: 12, maxHeight: 14)
        }
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text(label.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(1.5)
        }
    }
}
