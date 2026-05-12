import AppIntents
import WidgetKit

/// Stage 1: pick a weight delta. Updates LockScreenWorkoutState.stagedWeight
/// and advances stage to .reps. Lock-screen widget refreshes to show stage 2.
struct StageWeightDeltaIntent: AppIntent {
    static var openAppWhenRun: Bool { false }
    static var title: LocalizedStringResource = "Stage weight delta"
    static var description = IntentDescription("Stage a weight delta for the next set.")

    @Parameter(title: "Delta") var delta: Double

    init() {}
    init(delta: Double) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        guard state.inProgress, state.stage == .weight else { return .result() }
        state.stagedWeight = max(0, state.lastWeight + delta)
        state.stage = .reps
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 16.1, *) { await WorkoutLiveActivityRefresher.refresh() }
        return .result()
    }
}

/// Stage 2: pick a rep delta. Commits the set via WorkoutProgress, advances
/// to the next set's stage 1, and refreshes the widget + Live Activity.
struct CommitRepDeltaIntent: AppIntent {
    static var openAppWhenRun: Bool { false }
    static var title: LocalizedStringResource = "Commit rep delta"
    static var description = IntentDescription("Log this set with the given rep delta and advance.")

    @Parameter(title: "Rep delta") var delta: Int

    init() {}
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        guard state.inProgress else { return .result() }

        let weight: Double
        let bandColor: String?
        switch state.mode {
        case .free, .amrap:
            weight = state.stagedWeight ?? state.lastWeight
            bandColor = nil
        case .band:
            weight = 0
            bandColor = state.bandColor
        case .time:
            weight = 0
            bandColor = nil
        }

        let reps = max(0, state.lastReps + delta)

        WorkoutProgress.completeSet(
            exerciseKey: state.exerciseKey,
            setIndex: state.setIndex,
            weight: weight,
            reps: reps,
            bandColor: bandColor
        )

        state.setIndex += 1
        state.lastWeight = weight
        state.lastReps = reps
        if state.setIndex >= state.totalSets {
            // Current exercise done — advance to the next one if the host
            // app pre-populated a queue. Otherwise mark the workout complete.
            if !state.queue.isEmpty {
                let next = state.queue.removeFirst()
                state.exerciseKey = next.exerciseKey
                state.exerciseName = next.exerciseName
                state.setIndex = 0
                state.totalSets = next.totalSets
                state.lastWeight = next.lastWeight
                state.lastReps = next.lastReps
                state.mode = next.mode
                state.bandColor = next.bandColor
            } else {
                state.inProgress = false
            }
        }
        state.stage = .weight
        state.stagedWeight = nil
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 16.1, *) { await WorkoutLiveActivityRefresher.refresh() }
        return .result()
    }
}

/// For band exercises, stage 1 cycles through the 5 BandColor cases.
/// `direction = -1` (prev) | 0 (same) | +1 (next).
struct BandColorCycleIntent: AppIntent {
    static var openAppWhenRun: Bool { false }
    static var title: LocalizedStringResource = "Cycle band color"

    @Parameter(title: "Direction") var direction: Int

    init() {}
    init(direction: Int) { self.direction = direction }

    private static let cycle: [String] = ["yellow", "red", "green", "blue", "black"]

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        guard state.inProgress, state.mode == .band, state.stage == .weight else {
            return .result()
        }
        let current = state.bandColor ?? "green"
        let idx = Self.cycle.firstIndex(of: current) ?? 2
        let newIdx = max(0, min(Self.cycle.count - 1, idx + direction))
        state.bandColor = Self.cycle[newIdx]
        state.stage = .reps
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 16.1, *) { await WorkoutLiveActivityRefresher.refresh() }
        return .result()
    }
}

/// Powers the "End workout" button in the Dynamic Island expanded region.
/// Flips inProgress=false, ends every Live Activity immediately, and
/// reloads widget timelines so the rectangular widget reverts to NextUp.
/// Intentionally NOT exposed on the lock-screen surface (per spec — too
/// easy to fat-finger from a glanceable surface).
struct EndWorkoutIntent: AppIntent {
    static var openAppWhenRun: Bool { false }
    static var title: LocalizedStringResource = "End workout"
    static var description = IntentDescription("End the current workout session.")

    init() {}

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        state.inProgress = false
        LockScreenWorkoutStore.save(state)
        if #available(iOS 16.1, *) { await WorkoutLiveActivityRefresher.endAllImmediate() }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
