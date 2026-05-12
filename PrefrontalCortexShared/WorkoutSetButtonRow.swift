import SwiftUI
import AppIntents

/// Per-surface layout knob. `compactLockScreen` matches the rectangular
/// widget's tight padding; `island` slightly larger to meet the HIG 44×28
/// minimum tap target inside the Dynamic Island expanded region.
enum WorkoutSetButtonRowLayout {
    case compactLockScreen
    case island

    var verticalPadding: CGFloat {
        switch self {
        case .compactLockScreen: return 7
        case .island:            return 8
        }
    }
    var horizontalSpacing: CGFloat {
        switch self {
        case .compactLockScreen: return 6
        case .island:            return 8
        }
    }
    var font: Font {
        switch self {
        case .compactLockScreen: return .footnote.monospaced().weight(.semibold)
        case .island:            return .footnote.monospaced().weight(.semibold)
        }
    }
    var cornerRadius: CGFloat {
        switch self {
        case .compactLockScreen: return 10
        case .island:            return 12
        }
    }
}

/// Three-button row driven by `LockScreenWorkoutState`. Used by:
///   • `WorkoutLockWidget` (lock-screen rectangular widget)
///   • `WorkoutLiveActivityView` (lock-screen activity surface AND the
///     Dynamic Island expanded region)
///
/// Identical AppIntent wiring on every surface so a tap on the widget,
/// the lock-screen activity, or the island all flow through the same
/// `StageWeightDeltaIntent` / `CommitRepDeltaIntent` / `BandColorCycleIntent`.
struct WorkoutSetButtonRow: View {
    let mode: LockScreenWorkoutState.Mode
    let stage: LockScreenWorkoutState.Stage
    let layout: WorkoutSetButtonRowLayout

    init(mode: LockScreenWorkoutState.Mode,
         stage: LockScreenWorkoutState.Stage,
         layout: WorkoutSetButtonRowLayout = .compactLockScreen) {
        self.mode = mode
        self.stage = stage
        self.layout = layout
    }

    /// Convenience for the rectangular widget, which reads the full state
    /// from the App Group at timeline-build time. The Live Activity must
    /// NOT use this — its body has to derive from `ContentState`, otherwise
    /// the rendered surface won't refresh on `activity.update(...)`.
    init(state: LockScreenWorkoutState, layout: WorkoutSetButtonRowLayout = .compactLockScreen) {
        self.init(mode: state.mode, stage: state.stage, layout: layout)
    }

    var body: some View {
        switch (mode, stage) {
        case (.time, _):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("−5s", intent: CommitRepDeltaIntent(delta: -5), color: .orange)
                lockButton("=",   intent: CommitRepDeltaIntent(delta: 0),  color: .white)
                lockButton("+5s", intent: CommitRepDeltaIntent(delta: 5),  color: .green)
            }
        case (.amrap, _):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("−1", intent: CommitRepDeltaIntent(delta: -1), color: .orange)
                lockButton("=",  intent: CommitRepDeltaIntent(delta: 0),  color: .white)
                lockButton("+1", intent: CommitRepDeltaIntent(delta: 1),  color: .green)
            }
        case (.band, .weight):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("←", intent: BandColorCycleIntent(direction: -1), color: .orange)
                lockButton("=", intent: BandColorCycleIntent(direction: 0),  color: .white)
                lockButton("→", intent: BandColorCycleIntent(direction: 1),  color: .green)
            }
        case (.band, .reps), (.free, .reps):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("−1", intent: CommitRepDeltaIntent(delta: -1), color: .orange)
                lockButton("=",  intent: CommitRepDeltaIntent(delta: 0),  color: .white)
                lockButton("+1", intent: CommitRepDeltaIntent(delta: 1),  color: .green)
            }
        case (.free, .weight):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("−5", intent: StageWeightDeltaIntent(delta: -5), color: .orange)
                lockButton("=",  intent: StageWeightDeltaIntent(delta: 0),  color: .white)
                lockButton("+5", intent: StageWeightDeltaIntent(delta: 5),  color: .green)
            }
        }
    }

    @ViewBuilder
    private func lockButton<I: AppIntent>(_ label: String, intent: I, color: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        Button(intent: intent) {
            Text(label)
                .font(layout.font)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout.verticalPadding)
                .background(color.opacity(0.10), in: shape)
                .overlay(shape.strokeBorder(color.opacity(0.30)))
        }
        .buttonStyle(.plain)
    }
}
