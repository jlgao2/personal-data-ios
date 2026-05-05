import WidgetKit
import SwiftUI

// MARK: - Provider

struct HeroProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeroEntry {
        HeroEntry(date: .now, snapshot: HeroProvider.demo)
    }
    func getSnapshot(in context: Context, completion: @escaping (HeroEntry) -> Void) {
        completion(HeroEntry(date: .now,
                             snapshot: WidgetSnapshotIO.load() ?? HeroProvider.demo))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HeroEntry>) -> Void) {
        let snap = WidgetSnapshotIO.load() ?? HeroProvider.demo
        let entry = HeroEntry(date: .now, snapshot: snap)
        // Refresh every 30 minutes — the main app writes new snapshots more often,
        // so this is the floor.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static var demo: WidgetSnapshot {
        WidgetSnapshot(
            updated_at: "—",
            hero_eyebrow: "ALL CLEAR · TODAY'S FOCUS",
            hero_sentence: "Pull + Lower + core. RHR steady, sleep on target.",
            hero_state: "ok",
            traffic_light: "green",
            intensity_pct: 100,
            session_label: "Pull + Lower + core",
            stack_done: 0, stack_total: 7,
            reach_out_top_name: nil, reach_out_top_attn: nil, reach_out_top_days: nil
        )
    }
}

struct HeroEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Widget

struct HeroWidget: Widget {
    let kind = "FrontalLobeHero"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HeroProvider()) { entry in
            HeroWidgetView(snapshot: entry.snapshot)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Frontal Lobe · Now")
        .description("Today's most-actionable signal at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

// MARK: - View

struct HeroWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) var family

    var lightColor: Color {
        switch snapshot.traffic_light {
        case "green": return .green
        case "amber": return .cyan
        case "red":   return .red
        default:      return .secondary
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(snapshot.traffic_light.uppercased()) · \(snapshot.session_label)")
        case .accessoryCircular:
            ZStack {
                Circle().stroke(lightColor, lineWidth: 2)
                VStack(spacing: 0) {
                    Text("\(snapshot.intensity_pct)")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(lightColor)
                    Text(snapshot.traffic_light.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(lightColor)
                        .tracking(1.5)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.hero_eyebrow.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(lightColor)
                    .tracking(1.5)
                Text(snapshot.hero_sentence)
                    .font(.caption.italic())
                    .lineLimit(2)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.hero_eyebrow.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(lightColor)
                    .tracking(2)
                Text(snapshot.hero_sentence)
                    .font(.body.italic())
                    .foregroundStyle(.white)
                    .lineLimit(family == .systemMedium ? 4 : 3)
                Spacer(minLength: 0)
                HStack {
                    Text(snapshot.traffic_light.uppercased())
                        .font(.caption2.monospaced().weight(.bold))
                        .tracking(2)
                        .foregroundStyle(lightColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(lightColor, lineWidth: 1))
                    Text("\(snapshot.intensity_pct)% intensity")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}
