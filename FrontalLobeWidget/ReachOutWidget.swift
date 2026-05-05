import WidgetKit
import SwiftUI

// MARK: - Provider

struct ReachOutProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReachOutEntry {
        ReachOutEntry(date: .now, snapshot: HeroProvider.demo)
    }
    func getSnapshot(in context: Context, completion: @escaping (ReachOutEntry) -> Void) {
        completion(ReachOutEntry(date: .now,
                                 snapshot: WidgetSnapshotIO.load() ?? HeroProvider.demo))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReachOutEntry>) -> Void) {
        let snap = WidgetSnapshotIO.load() ?? HeroProvider.demo
        let entry = ReachOutEntry(date: .now, snapshot: snap)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60))))
    }
}

struct ReachOutEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Widget

struct ReachOutWidget: Widget {
    let kind = "FrontalLobeReachOut"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReachOutProvider()) { entry in
            ReachOutWidgetView(snapshot: entry.snapshot)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Frontal Lobe · Reach Out")
        .description("Top person needing attention today.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - View

struct ReachOutWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) var family

    var name: String { snapshot.reach_out_top_name ?? "—" }
    var attn: Int { snapshot.reach_out_top_attn ?? 0 }
    var days: Int { snapshot.reach_out_top_days ?? 0 }

    var attnColor: Color {
        if attn >= 60 { return .red }
        if attn >= 30 { return .cyan }
        return .secondary
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(name) · \(days)d · attn \(attn)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("REACH OUT")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(1.5)
                Text(name).font(.caption.italic()).lineLimit(1)
                Text("\(days)d since last · attn \(attn)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(attnColor)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("REACH OUT")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                if snapshot.reach_out_top_name == nil {
                    Text("All clear today.")
                        .font(.body.italic())
                        .foregroundStyle(.green)
                } else {
                    Text(name)
                        .font(.body.italic())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    HStack {
                        Text("ATTN \(attn)")
                            .font(.caption2.monospaced().bold())
                            .tracking(2)
                            .foregroundStyle(attnColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(attnColor, lineWidth: 1))
                        Spacer()
                        Text("\(days)d")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
