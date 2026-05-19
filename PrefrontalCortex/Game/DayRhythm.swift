import Foundation

/// Single source of truth for the day's felt arc. Pure — `now` and
/// `closing` are injected so progress/escalation are deterministic.
/// Derived from DailyLock + DeviationStore + AuthorshipStore + the
/// clock; there is no persisted day-state machine.
struct DayRhythm {
    enum Escalation { case none, gentle, pressing, closing }

    let now: Date
    /// True ONLY while the rollover transition overlay is on screen.
    let closing: Bool

    init(now: Date = Date(), closing: Bool = false) {
        self.now = now
        self.closing = closing
    }

    /// Authored slots done ÷ total (same set the chip renders).
    var progressFraction: Double {
        let slots = DailyLockSlots.visible(date: now)
        guard !slots.isEmpty else { return 1 }
        return Double(slots.filter { $0.done }.count) / Double(slots.count)
    }

    var isDayComplete: Bool { progressFraction >= 1.0 }

    /// Resolved = explicitly done, a deviation logged for it today, or
    /// authorship-outside (doesn't gate / doesn't escalate).
    var workoutResolved: Bool {
        if AuthorshipStore.get(.workout) == .outside { return true }
        if DailyLock.isWorkoutDone(date: now) { return true }
        if DeviationStore.entry(for: .workout, date: now) != nil { return true }
        return false
    }

    var escalation: Escalation {
        if workoutResolved { return .none }
        if closing { return .closing }
        switch TimeBand.current(at: now) {
        case .reachOut: return .gentle     // 19–22, unresolved
        case .night:    return .pressing   // 22–06, unresolved
        default:        return .none
        }
    }

    /// Authored-slot tally for DayCloseView.
    func closeSummary() -> (resolved: Int, unresolved: Int,
                            slots: [(label: String, done: Bool)]) {
        let s = DailyLockSlots.visible(date: now)
        let done = s.filter { $0.done }.count
        return (done, s.count - done, s.map { ($0.label, $0.done) })
    }
}
