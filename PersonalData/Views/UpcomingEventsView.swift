import SwiftUI

/// Renders the next 5-10 calendar events. Prefers live EventKit data
/// when authorized; falls back to the bundle's CALENDAR (Google) array
/// when the iOS calendar isn't connected yet.
struct UpcomingEventsView: View {
    let bundleEvents: [CalendarEvent]
    @ObservedObject var store: CalendarStore

    private var liveCount: Int { store.upcoming.count }
    private var sourceLabel: String {
        if store.authorized { return "iOS · live" }
        if !bundleEvents.isEmpty { return "Google · synced" }
        return "not connected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CALENDAR")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                Text(sourceLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if store.authorized {
                if store.upcoming.isEmpty {
                    EmptyHint(text: "No events in next 14 days.")
                } else {
                    VStack(spacing: 1) {
                        ForEach(store.upcoming.prefix(10)) { e in
                            LiveEventRow(event: e)
                        }
                    }
                    .background(Color.white.opacity(0.05))
                }
            } else if !bundleEvents.isEmpty {
                VStack(spacing: 1) {
                    ForEach(bundleEvents.prefix(10)) { e in
                        BundleEventRow(event: e)
                    }
                }
                .background(Color.white.opacity(0.05))
            } else {
                EmptyHint(text: "Tap to grant calendar access. We'll show your next 14 days here and let you add reminders from Goals + Reach Out.")
                Button("Connect calendar") {
                    Task {
                        await store.requestAccess()
                        if store.authorized {
                            await store.loadUpcoming()
                        }
                    }
                }
                .font(.caption.monospaced())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(.cyan)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.cyan, lineWidth: 1)
                )
                .padding(.top, 4)
            }
            if let err = store.lastError {
                Text(err)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
    }
}

private struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.italic())
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.4))
            .border(Color.white.opacity(0.05), width: 1)
    }
}

private struct LiveEventRow: View {
    let event: LiveCalendarEvent

    private var when: String {
        let f = DateFormatter()
        if event.isAllDay {
            f.dateFormat = "MMM d"
            return f.string(from: event.start) + " · all day"
        }
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: event.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(when.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.cyan)
                .tracking(1.5)
            Text(event.summary)
                .font(.body.italic())
                .foregroundStyle(.white)
            if let loc = event.location {
                Text(loc)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }
}

private struct BundleEventRow: View {
    let event: CalendarEvent

    private var when: String {
        guard let s = event.start else { return "—" }
        if s.count == 10 { return s + " · all day" }
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: s) else { return s }
        let df = DateFormatter()
        df.dateFormat = "MMM d · h:mm a"
        return df.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(when.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.cyan)
                .tracking(1.5)
            Text(event.summary ?? "(no title)")
                .font(.body.italic())
                .foregroundStyle(.white)
            if let loc = event.location {
                Text(loc)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }
}
