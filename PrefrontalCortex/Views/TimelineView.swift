import SwiftUI

/// Unified Today timeline. Merges calendar events + scheduled supplements +
/// workout anchor + reach-out pinned to evening into one chronological list.
/// Past rows dim, current 90-min window glows, future-far fades.
struct TimelineView: View {
    let bundle: IOSBundle
    @ObservedObject var calStore: CalendarStore

    @State private var stackState: [String: Bool] = readState(key: "stack")
    @State private var reachState: [String: Bool] = readState(key: "reachout")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY · CHRONOLOGICAL")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            ZStack(alignment: .leading) {
                // Vertical track behind the dot column
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .offset(x: 84)
                VStack(spacing: 0) {
                    let items = buildItems()
                    if items.isEmpty {
                        Text("No timeline items today.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(items) { it in
                            TimelineRow(item: it,
                                        isDone: doneForItem(it),
                                        toggle: { toggle(it) })
                                .overlay(Divider().opacity(0.3), alignment: .bottom)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.4))
            .overlay(Rectangle().stroke(Color.white.opacity(0.05), lineWidth: 1))
        }
    }

    // MARK: - Items

    private func buildItems() -> [TimelineItem] {
        var items: [TimelineItem] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: today) else { return [] }

        // Calendar events (today)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let altF = ISO8601DateFormatter()
        let candidates: [CalendarEvent] = bundle.calendar ?? []
        for e in candidates {
            guard let s = e.start, let date = f.date(from: s) ?? altF.date(from: s) else { continue }
            if date < today || date >= todayEnd { continue }
            items.append(.init(kind: .calendar, time: date,
                               title: e.summary ?? "(no title)",
                               detail: e.location ?? "",
                               stateKey: nil, stateId: nil, pill: nil, url: e.url))
        }

        // Supps used to render as one timeline row per supplement (7 rows for
        // 7 supps). They've moved out to StackView's morning/evening checklist
        // — the timeline stays for genuinely time-sensitive things.

        // Workout used to render here at 11am for non-rest days. Moved out:
        // AdaptedSessionView handles today's session below the timeline, and
        // the new WorkoutSessionView (full-screen tracker) is the place to
        // actually do the work.

        // Reach out — top unmarked person at 8pm
        let reachList: [SocialPerson] = bundle.social?.reach_out ?? []
        let topUnmarked: SocialPerson? = reachList.first { p in
            let pid = p.id ?? p.name ?? ""
            return !(reachState[pid] ?? false)
        }
        if let top = topUnmarked {
            var comps = cal.dateComponents([.year, .month, .day], from: today)
            comps.hour = 20
            if let t = cal.date(from: comps) {
                let daysFmt: String = top.days_since_last.map { "\($0)d since last" } ?? ""
                let detail = top.about_what ?? daysFmt
                let title = "Reach out: \(top.name ?? "Friend")"
                items.append(.init(kind: .reachOut, time: t,
                                   title: title,
                                   detail: detail,
                                   stateKey: "reachout",
                                   stateId: top.id ?? top.name,
                                   pill: nil, url: nil))
            }
        }

        return items.sorted { $0.time < $1.time }
    }

    private func doneForItem(_ it: TimelineItem) -> Bool {
        guard let key = it.stateKey, let id = it.stateId else { return false }
        return key == "stack" ? (stackState[id] ?? false) : (reachState[id] ?? false)
    }

    private func toggle(_ it: TimelineItem) {
        guard let key = it.stateKey, let id = it.stateId else { return }
        if key == "stack" {
            stackState[id] = !(stackState[id] ?? false)
            writeState(key: "stack", state: stackState)
        } else {
            reachState[id] = !(reachState[id] ?? false)
            writeState(key: "reachout", state: reachState)
        }
    }

    // MARK: - Per-day localStorage equivalent

    private static func todayKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private static func readState(key: String) -> [String: Bool] {
        let k = "tl_\(key)_\(todayKey())"
        guard let data = UserDefaults.standard.data(forKey: k),
              let m = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return m
    }
    private func writeState(key: String, state: [String: Bool]) {
        let k = "tl_\(key)_\(Self.todayKey())"
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: k)
        }
    }
}

private func todaysProgramKeyiOS() -> String {
    let dow = Calendar.current.component(.weekday, from: Date()) // 1=Sun
    let mondayBased = ((dow + 5) % 7) + 1
    return "Day \(mondayBased)"
}

// MARK: - Models

struct TimelineItem: Identifiable {
    enum Kind { case calendar, supplement, workout, reachOut }
    let id = UUID()
    let kind: Kind
    let time: Date
    let title: String
    let detail: String
    let stateKey: String?     // "stack" | "reachout" | nil
    let stateId: String?
    let pill: String?         // "green" | "amber" | "red"
    let url: String?
}

// MARK: - Row

private struct TimelineRow: View {
    let item: TimelineItem
    let isDone: Bool
    let toggle: () -> Void

    @State private var revealed = false

    enum Band { case past, now, soon, far }

    private var band: Band {
        let delta = item.time.timeIntervalSinceNow
        if delta < -30 * 60 { return .past }
        if delta < 90 * 60  { return .now }
        if delta < 6 * 3600 { return .soon }
        return .far
    }

    private var dotColor: Color {
        switch (item.kind, band) {
        case (_, .past): return .gray
        case (_, .now):  return .green
        case (.supplement, _): return Color.cyan.opacity(0.7)
        case (.workout, _):    return .green
        case (.reachOut, _):   return Color.cyan
        case (.calendar, _):   return Color.cyan.opacity(0.6)
        }
    }

    private var timeColor: Color {
        switch band {
        case .past: return .gray
        case .now:  return .green
        case .soon: return .cyan
        case .far:  return Color.gray.opacity(0.7)
        }
    }

    private var rowOpacity: Double {
        switch band {
        case .past: return 0.4
        case .now:  return 1.0
        case .soon: return 1.0
        case .far:  return 0.55
        }
    }

    private var pillColor: Color {
        switch item.pill {
        case "green": return .green
        case "amber": return .cyan
        case "red":   return .red
        default:      return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(formattedTime(item.time))
                .font(.caption.monospaced())
                .tracking(1.5)
                .foregroundStyle(timeColor)
                .frame(width: 72, alignment: .leading)

            ZStack {
                if band == .now {
                    Circle().fill(dotColor.opacity(0.18))
                        .frame(width: 18, height: 18)
                }
                Circle().fill(dotColor)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.body.italic())
                        .foregroundStyle(.white)
                        .strikethrough(isDone, color: .green)
                    Spacer()
                    if let pill = item.pill {
                        Text(pill.uppercased())
                            .font(.caption2.monospaced().bold())
                            .tracking(2)
                            .foregroundStyle(pillColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(pillColor, lineWidth: 1))
                    }
                }
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.footnote.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(revealed ? rowOpacity : 0)
        .offset(y: revealed ? 0 : 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.stateKey != nil { toggle() }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { revealed = true }
        }
    }

    private func formattedTime(_ t: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"; f.pmSymbol = "pm"
        return f.string(from: t).lowercased()
    }
}
