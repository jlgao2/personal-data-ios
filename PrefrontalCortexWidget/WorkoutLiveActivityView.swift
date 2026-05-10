import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// The Live Activity declaration for the in-progress workout.
///
/// ActivityKit forces this to live in the widget extension (same place
/// `Widget` types live). The host app starts/updates/ends activities by
/// calling into ActivityKit directly (`WorkoutLiveActivity` facade);
/// rendering is entirely done here.
struct WorkoutLiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            // Lock-screen / banner presentation
            WorkoutLiveActivityLockScreenView(
                attrs: context.attributes,
                content: context.state
            )
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — long-press to reveal
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.exerciseName.uppercased())
                        .font(.footnote.monospaced().bold())
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("SET \(context.state.setIndex + 1)/\(context.state.totalSets)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(IslandSubtitle.text(content: context.state))
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.7))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isComplete {
                        completeBanner
                    } else {
                        VStack(spacing: 6) {
                            WorkoutSetButtonRow(
                                state: LockScreenWorkoutStore.load(),
                                layout: .island
                            )
                            Divider().background(.white.opacity(0.2))
                            Button(intent: EndWorkoutIntent()) {
                                Text("End workout")
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.red.opacity(0.4)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: {
                IslandDots(setIndex: context.state.setIndex,
                           totalSets: context.state.totalSets)
            } compactTrailing: {
                Text("\(context.state.setIndex + 1)/\(context.state.totalSets)")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.cyan)
            } minimal: {
                IslandRing(setIndex: context.state.setIndex,
                           totalSets: context.state.totalSets)
            }
            .keylineTint(.cyan)
        }
    }

    @ViewBuilder
    private var completeBanner: some View {
        Text("✓ WORKOUT COMPLETE")
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// MARK: - Lock-screen view

private struct WorkoutLiveActivityLockScreenView: View {
    let attrs: WorkoutLiveActivityAttributes
    let content: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SET \(content.setIndex + 1)/\(content.totalSets)")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.cyan)
                    .tracking(1.5)
                Spacer()
                Text(content.exerciseName.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if content.isComplete {
                Text("✓ WORKOUT COMPLETE")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.top, 6)
            } else {
                Text(IslandSubtitle.text(content: content))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                // The lock-screen surface intentionally OMITS the End
                // button — the spec calls that out as island-only because
                // the lock screen surface is glanceable, not interactive
                // for high-stakes operations.
                WorkoutSetButtonRow(
                    state: LockScreenWorkoutStore.load(),
                    layout: .compactLockScreen
                )
            }
        }
        .padding(8)
    }
}

// MARK: - Subtitle formatter (shared between lock + island)

private enum IslandSubtitle {
    static func text(content: WorkoutLiveActivityAttributes.ContentState) -> String {
        switch content.mode {
        case "free", "amrap":
            if content.stage == "reps", let staged = content.stagedWeight {
                return "staged \(formatWeight(staged, unit: content.unit)) × ?"
            }
            return "last \(formatWeight(content.lastWeight, unit: content.unit)) × \(content.lastReps)"
        case "band":
            let color = content.bandColor ?? "—"
            return "last \(color) × \(content.lastReps)"
        case "time":
            return "last \(content.lastReps) sec"
        default:
            return ""
        }
    }
    private static func formatWeight(_ w: Double, unit: String) -> String {
        if w == 0 { return "BW" }
        let trimmed = w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))" : String(format: "%g", w)
        return "\(trimmed) \(unit)"
    }
}

// MARK: - Compact leading dots

private struct IslandDots: View {
    let setIndex: Int
    let totalSets: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(totalSets, 1), id: \.self) { i in
                Circle()
                    .fill(i < setIndex ? Color.cyan : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.leading, 2)
    }
}

// MARK: - Minimal ring

private struct IslandRing: View {
    let setIndex: Int
    let totalSets: Int
    var body: some View {
        let frac = totalSets > 0 ? Double(setIndex) / Double(totalSets) : 0
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, frac))
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
    }
}
