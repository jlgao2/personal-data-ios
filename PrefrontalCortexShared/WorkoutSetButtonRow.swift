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
        case .compactLockScreen: return 4
        case .island:            return 6
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
        case .compactLockScreen: return .caption.monospaced().weight(.semibold)
        case .island:            return .footnote.monospaced().weight(.semibold)
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
    let state: LockScreenWorkoutState
    let layout: WorkoutSetButtonRowLayout

    init(state: LockScreenWorkoutState, layout: WorkoutSetButtonRowLayout = .compactLockScreen) {
        self.state = state
        self.layout = layout
    }

    var body: some View {
        switch (state.mode, state.stage) {
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
        Button(intent: intent) {
            Text(label)
                .font(layout.font)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout.verticalPadding)
                .background(color.opacity(0.15), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}
