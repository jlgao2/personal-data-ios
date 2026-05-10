import WidgetKit
import SwiftUI
import AppIntents

struct WorkoutLockProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutLockEntry {
        WorkoutLockEntry(date: .now, state: .idle)
    }
    func getSnapshot(in context: Context, completion: @escaping (WorkoutLockEntry) -> Void) {
        completion(WorkoutLockEntry(date: .now, state: LockScreenWorkoutStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutLockEntry>) -> Void) {
        let state = LockScreenWorkoutStore.load()
        let entry = WorkoutLockEntry(date: .now, state: state)
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WorkoutLockEntry: TimelineEntry {
    let date: Date
    let state: LockScreenWorkoutState
}

struct WorkoutLockWidget: Widget {
    let kind = "PrefrontalCortexWorkoutLock"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutLockProvider()) { entry in
            WorkoutLockView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Prefrontal Cortex · Next set")
        .description("Log the next set without unlocking. Falls back to NextUp when no workout is active.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

struct WorkoutLockView: View {
    let entry: WorkoutLockEntry

    var body: some View {
        if entry.state.inProgress {
            activeView
        } else {
            idleNextUpView
        }
    }

    @ViewBuilder
    private var activeView: some View {
        let s = entry.state
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SET \(s.setIndex + 1)/\(s.totalSets)")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.cyan)
                    .tracking(1.5)
                Spacer()
                Text(s.exerciseName.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(baselineText(s))
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.7))
            WorkoutSetButtonRow(state: s, layout: .compactLockScreen)
        }
        .padding(8)
    }

    @ViewBuilder
    private var idleNextUpView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No workout in progress")
                .font(.caption.italic())
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private func baselineText(_ s: LockScreenWorkoutState) -> String {
        switch s.mode {
        case .free, .amrap:
            let stagedDisplay = s.stage == .reps && s.stagedWeight != nil
                ? "staged \(formatWeight(s.stagedWeight!, unit: s.unit)) × ?"
                : "last \(formatWeight(s.lastWeight, unit: s.unit)) × \(s.lastReps)"
            return stagedDisplay
        case .band:
            let color = s.bandColor ?? "—"
            return "last \(color) × \(s.lastReps)"
        case .time:
            return "last \(s.lastReps) sec"
        }
    }

    private func formatWeight(_ w: Double, unit: String) -> String {
        if w == 0 { return "BW" }
        let trimmed = w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))" : String(format: "%g", w)
        return "\(trimmed) \(unit)"
    }

}
