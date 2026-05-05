import WidgetKit
import SwiftUI

// MARK: - Provider

struct SessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionEntry {
        SessionEntry(date: .now, snapshot: HeroProvider.demo)
    }
    func getSnapshot(in context: Context, completion: @escaping (SessionEntry) -> Void) {
        completion(SessionEntry(date: .now,
                                snapshot: WidgetSnapshotIO.load() ?? HeroProvider.demo))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
        let snap = WidgetSnapshotIO.load() ?? HeroProvider.demo
        let entry = SessionEntry(date: .now, snapshot: snap)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct SessionEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Widget

struct SessionWidget: Widget {
    let kind = "FrontalLobeSession"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SessionProvider()) { entry in
            SessionWidgetView(snapshot: entry.snapshot)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Frontal Lobe · Session + Stack")
        .description("Today's session label, intensity, and stack adherence.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - View

struct SessionWidgetView: View {
    let snapshot: WidgetSnapshot

    private var stackPct: Double {
        guard snapshot.stack_total > 0 else { return 0 }
        return Double(snapshot.stack_done) / Double(snapshot.stack_total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY · SESSION")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            Text(snapshot.session_label)
                .font(.body.italic())
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            // Stack progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("STACK")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .tracking(2)
                    Spacer()
                    Text("\(snapshot.stack_done) / \(snapshot.stack_total)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(stackPct >= 1.0 ? .green : .cyan)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.1))
                        Rectangle()
                            .fill(stackPct >= 1.0 ? Color.green : Color.cyan)
                            .frame(width: geo.size.width * stackPct)
                    }
                    .frame(height: 4)
                }
                .frame(height: 4)
            }
        }
    }
}
