import WidgetKit
import SwiftUI

// MARK: - Provider

/// Reads the `next_up` array from the App-Group snapshot and builds a
/// multi-entry timeline — one entry at "now" with the next item, then one
/// per future item at its own time. WidgetKit auto-advances between them.
struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        NextUpEntry(date: .now, item: Self.demo)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        completion(NextUpEntry(date: .now,
                               item: nextItem(after: .now) ?? Self.demo))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let snap = WidgetSnapshotIO.load()
        let items = (snap?.next_up ?? []).compactMap { i -> (Date, NextUpItem)? in
            guard let d = parseISO(i.time_iso) else { return nil }
            return (d, i)
        }

        let now = Date()
        var entries: [NextUpEntry] = []

        // First entry: "right now, here's what's next"
        if let first = items.first(where: { $0.0 > now }) {
            entries.append(NextUpEntry(date: now, item: first.1))
            // Each subsequent item gets its own entry at its own time so the
            // widget rolls forward without needing a new snapshot.
            for (date, item) in items where date > now {
                entries.append(NextUpEntry(date: date, item: item))
            }
        } else {
            entries.append(NextUpEntry(date: now, item: Self.demoQuiet))
        }

        // Refresh the snapshot floor: one hour, capped to next item's time.
        let refresh = entries.dropFirst().first?.date ?? now.addingTimeInterval(60 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func nextItem(after date: Date) -> NextUpItem? {
        let snap = WidgetSnapshotIO.load()
        return (snap?.next_up ?? []).first {
            if let d = parseISO($0.time_iso) { return d > date }
            return false
        }
    }

    private func parseISO(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    static let demo = NextUpItem(
        time_iso: ISO8601DateFormatter().string(from: Date().addingTimeInterval(45 * 60)),
        title: "Morning supps",
        kind: "supps_morning"
    )
    static let demoQuiet = NextUpItem(
        time_iso: ISO8601DateFormatter().string(from: Date()),
        title: "Day's clear",
        kind: "calendar"
    )
}

struct NextUpEntry: TimelineEntry {
    let date: Date
    let item: NextUpItem
}

// MARK: - Widget

struct NextUpWidget: Widget {
    let kind = "PrefrontalCortexNextUp"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextUpProvider()) { entry in
            NextUpView(entry: entry)
        }
        .configurationDisplayName("Prefrontal Cortex · Next up")
        .description("The next thing on today's chronological list.")
        .supportedFamilies([
            .accessoryRectangular,   // lock screen rectangle
            .accessoryInline,        // lock screen one-liner above the date
            .accessoryCircular,      // small dot above the date
            .systemSmall,            // home screen
        ])
    }
}

// MARK: - Views

struct NextUpView: View {
    let entry: NextUpEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryInline:      inline
        case .accessoryCircular:    circular
        default:                    homeSmall
        }
    }

    // Lock-screen rectangle — the headline use case.
    private var rectangular: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: entry.item.symbol)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(timeString.uppercased())
                    .font(.caption2.monospaced())
                    .opacity(0.75)
                Text(entry.item.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color.black }
    }

    // Single line above the lock-screen clock.
    private var inline: some View {
        HStack {
            Image(systemName: entry.item.symbol)
            Text("\(timeString) · \(entry.item.title)")
        }
    }

    // Tiny circular complication.
    private var circular: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1)
            VStack(spacing: 0) {
                Image(systemName: entry.item.symbol)
                    .font(.caption2)
                Text(timeString.replacingOccurrences(of: " ", with: ""))
                    .font(.system(size: 8, design: .monospaced))
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }

    // Home-screen small (cyan glow on dark, matches app aesthetic).
    private var homeSmall: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEXT · \(timeString.uppercased())")
                .font(.caption2.monospaced())
                .foregroundStyle(.cyan)
                .tracking(1.5)
            Spacer()
            Image(systemName: entry.item.symbol)
                .font(.title2)
                .foregroundStyle(.cyan)
            Text(entry.item.title)
                .font(.body.italic())
                .foregroundStyle(.white)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.black }
    }

    private var timeString: String {
        guard let date = parse(entry.item.time_iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date).lowercased()
    }

    private func parse(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
}
