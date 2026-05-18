import Foundation

/// The ONE place that touches the deviation API for the week-makeup
/// "undo" affordance. Tapping "Undo" on `WeekMakeupBanner` means the
/// user is overriding the pipeline's make-up redistribution by locking
/// in a *skip* for the originally-skipped training day — a SKIP
/// `DeviationEntry` on the workout surface with `lockIn = true`. Keeping
/// all deviation-API-dependent code here isolates the contract from the
/// view layer.
enum DeviationUndo {

    /// Maps an ISO weekday short-name ("Mon".."Sun") to the most recent
    /// past-or-today date at local start-of-day for that weekday.
    private static func startOfDay(forWeekday wd: String?) -> Date? {
        let names = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        guard let wd, let idx = names.firstIndex(of: wd) else { return nil }
        let targetISO = idx + 1
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: Date())
        let todayISO = cal.component(.weekday, from: today) == 1
            ? 7 : cal.component(.weekday, from: today) - 1
        let back = (todayISO - targetISO + 7) % 7
        return cal.date(byAdding: .day, value: -back, to: today)
    }

    /// Lock in a SKIP on the workout surface for the skipped training
    /// day. No-op if `weekday` is nil or unparseable.
    static func submitSkipLockIn(weekday: String?) {
        guard let date = startOfDay(forWeekday: weekday) else { return }

        let entry = DeviationEntry(
            ts: date,
            surface: .workout,
            surfaceID: nil,
            direction: .didSkip,
            cause: nil,
            prescribed: "",
            actual: "",
            actualQuant: nil,
            lockIn: true,
            note: nil
        )
        DeviationStore.record(entry, date: date)

        let upload = DeviationUpload(
            client_id: DeviationStore.clientID(surface: .workout,
                                               surfaceID: nil,
                                               date: date),
            ts: ISO8601DateFormatter().string(from: date),
            surface: DeviationEntry.Surface.workout.rawValue,
            surface_id: nil,
            direction: DeviationEntry.Direction.didSkip.rawValue,
            cause: nil,
            prescribed: "",
            actual: "",
            actual_quant: nil,
            lock_in: true,
            note: nil
        )
        Task { try? await iCloudTransport.shared.uploadDeviations([upload]) }
    }
}
