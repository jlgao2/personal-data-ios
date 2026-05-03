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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
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

