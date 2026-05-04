import SwiftUI

/// Social tab content. Two panels: reach-out (sorted by attention score)
/// and upcoming birthdays. Sourced from sibling social-media-graph repo
/// aggregates — no raw chat content beyond the curated excerpts that
/// repo already chose to expose.
struct SocialView: View {
    let summary: SocialSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ReachOutView(people: summary.reach_out ?? [])
            BirthdaysView(birthdays: summary.birthdays ?? [])
        }
    }
}

// MARK: - Reach Out

private struct ReachOutView: View {
    let people: [SocialPerson]

    private static func tier(_ score: Int?) -> (Color, String) {
        guard let s = score else { return (.secondary, "low") }
        if s >= 60 { return (.red, "high") }
        if s >= 30 { return (.cyan, "medium") }
        return (.secondary, "low")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("REACH OUT")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                Text("\(people.count) people")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 1) {
                ForEach(people) { p in PersonRow(person: p) }
            }
            .background(Color.white.opacity(0.05))
        }
    }
}

private struct PersonRow: View {
    let person: SocialPerson
    @ObservedObject private var calStore = CalendarStore.shared
    @State private var scheduled = false
    @State private var scheduleError: String? = nil

    private var tierColor: Color {
        switch person.attention_score ?? 0 {
        case 60...:    return .red
        case 30..<60:  return .cyan
        default:       return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(person.name ?? "(unknown)")
                    .font(.body.italic())
                    .foregroundStyle(.white)
                Spacer()
                Text("attn \(person.attention_score ?? 0)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(tierColor)
            }
            HStack {
                if let d = person.days_since_last {
                    Text("\(d)d since last")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let from = person.last_msg_from {
                    Text("· \(from == "me" ? "you" : "them")")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let about = person.about_what {
                Text(about)
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let excerpt = person.last_excerpt, !excerpt.isEmpty {
                Text("“\(excerpt)”")
                    .font(.caption.monospaced())
                    .foregroundStyle(.gray)
                    .italic()
                    .lineLimit(1)
            }
            // Calendar action: create a 30-min check-in event tomorrow at 10am.
            if calStore.authorized, !scheduled {
                Button(action: { Task { await scheduleCheckIn() } }) {
                    Text("+ SCHEDULE CHECK-IN")
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
            if scheduled {
                Text("✓ ADDED TO CALENDAR")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.green)
                    .tracking(2)
                    .padding(.top, 4)
            }
            if let e = scheduleError {
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

    private func scheduleCheckIn() async {
        var when = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: when)
        comps.hour = 10
        when = Calendar.current.date(from: comps) ?? when
        let title = "Reach out: \(person.name ?? "Friend")"
        let notes = [person.about_what, person.last_excerpt.map { "Last: \"\($0)\"" }]
            .compactMap { $0 }.joined(separator: "\n\n")
        let ok = await calStore.createEvent(title: title, date: when,
                                            duration: 30 * 60, notes: notes)
        if ok { scheduled = true } else { scheduleError = calStore.lastError }
    }
}

// MARK: - Birthdays

private let MONTHS = ["Jan","Feb","Mar","Apr","May","Jun",
                      "Jul","Aug","Sep","Oct","Nov","Dec"]

private struct BirthdaysView: View {
    let birthdays: [SocialBirthday]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BIRTHDAYS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                Text("next 60 days")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if birthdays.isEmpty {
                Text("No birthdays in next 60 days.")
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4))
                    .border(Color.white.opacity(0.05), width: 1)
            } else {
                VStack(spacing: 1) {
                    ForEach(birthdays) { b in BirthdayRow(b: b) }
                }
                .background(Color.white.opacity(0.05))
            }
        }
    }
}

private struct BirthdayRow: View {
    let b: SocialBirthday

    private var dateStr: String {
        guard let m = b.month, let d = b.day, m >= 1, m <= 12 else { return "—" }
        return "\(MONTHS[m - 1]) \(d)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.name ?? "(unknown)")
                    .font(.body.italic())
                    .foregroundStyle(.white)
                if let yk = b.year_known, yk == false {
                    Text("year unknown")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(dateStr)
                    .font(.caption.monospaced())
                    .foregroundStyle(.cyan)
                if let d = b.days_until {
                    Text("in \(d)d")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }
}

