import Foundation

/// The authored daily-lock slots, shared by DailyLockChip (rendering)
/// and DayRhythm (progress) so the two cannot diverge. This mirrors
/// DailyLockChip's PRE-EXISTING slot set exactly (no embodiment slot —
/// matching the chip's prior behavior; DailyLock.isComplete's broader
/// gate is unchanged and unrelated to this progress capsule).
enum DailyLockSlots {
    struct Slot: Identifiable {
        let id: String
        let label: String
        let surface: AuthorshipSurface?   // nil = custom slot (always gates)
        let done: Bool
        let toggle: (() -> Void)?
    }

    /// Built-in slots not tagged authorship-outside, then custom slots.
    static func visible(date: Date = Date()) -> [Slot] {
        var out: [Slot] = []
        let builtIn: [(String, String, AuthorshipSurface, Bool, (() -> Void)?)] = [
            ("workout",    "W",     .workout,    DailyLock.isWorkoutDone(date: date),       nil),
            ("supps_am",   "AM",    .suppsAM,    DailyLock.isAMSuppsDone(date: date),       nil),
            ("supps_pm",   "PM",    .suppsPM,    DailyLock.isPMSuppsDone(date: date),       nil),
            ("mindful",    "M",     .mindful,    DailyLock.isMindfulEatingDone(date: date), nil),
            ("skincareAM", "SK·AM", .skincareAM, DailyLock.isSkincareAMDone(date: date),
                { DailyLock.setSkincareAMDone(!DailyLock.isSkincareAMDone()) }),
            ("skincarePM", "SK·PM", .skincarePM, DailyLock.isSkincarePMDone(date: date),
                { DailyLock.setSkincarePMDone(!DailyLock.isSkincarePMDone()) }),
        ]
        for (id, label, surf, done, toggle) in builtIn
        where AuthorshipStore.get(surf) != .outside {
            out.append(Slot(id: id, label: label, surface: surf, done: done, toggle: toggle))
        }
        for c in CustomSlotStore.load() {
            out.append(Slot(id: "custom_\(c.id)", label: c.label, surface: nil,
                            done: CustomSlotStore.isDone(slotID: c.id),
                            toggle: { CustomSlotStore.toggle(slotID: c.id) }))
        }
        return out
    }
}
