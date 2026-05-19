import Foundation

/// The ONE place workout-slot resolution writes happen, so no view
/// touches DailyLock/DeviationStore write paths directly. Mirrors
/// DeviationUndo.swift's isolation discipline.
enum WorkoutReconcile {

    static func didIt(date: Date = Date()) {
        DailyLock.setWorkoutDone(source: .manual, date: date)
        Task { @MainActor in NotificationManager.shared.cancelWorkoutNudge() }
    }

    static func didRest(date: Date = Date()) {
        DailyLock.setWorkoutDone(source: .rest_ack, date: date)
        Task { @MainActor in NotificationManager.shared.cancelWorkoutNudge() }
    }

    static func skip(reason: String, date: Date = Date()) {
        DailyLock.setWorkoutDone(source: .skip, reason: reason, date: date)
        Task { @MainActor in NotificationManager.shared.cancelWorkoutNudge() }
    }

    /// Logged an off-plan workout. Marks the slot done AND records a
    /// did_different workout deviation for the engine.
    static func didElse(sport: String, date: Date = Date()) {
        DailyLock.setWorkoutDone(source: .manual, date: date)
        let entry = DeviationEntry(
            ts: date,
            surface: .workout,
            surfaceID: nil,
            direction: .didDifferent,
            cause: nil,
            prescribed: "",
            actual: sport,
            actualQuant: nil,
            lockIn: false,
            note: nil
        )
        _ = DeviationStore.record(entry, date: date)
        WorkoutReconcileBridge.upload(sport: sport, date: date)
        Task { @MainActor in NotificationManager.shared.cancelWorkoutNudge() }
    }
}

/// Holds the DeviationUpload construction + iCloudTransport call so the
/// upload-shape dependency lives in exactly one function.
enum WorkoutReconcileBridge {
    static func upload(sport: String, date: Date) {
        let upload = DeviationUpload(
            client_id: DeviationStore.clientID(surface: .workout,
                                               surfaceID: nil,
                                               date: date),
            ts: ISO8601DateFormatter().string(from: date),
            surface: DeviationEntry.Surface.workout.rawValue,
            surface_id: nil,
            direction: DeviationEntry.Direction.didDifferent.rawValue,
            cause: nil,
            prescribed: "",
            actual: sport,
            actual_quant: nil,
            lock_in: false,
            note: nil
        )
        Task { try? await iCloudTransport.shared.uploadDeviations([upload]) }
    }
}
