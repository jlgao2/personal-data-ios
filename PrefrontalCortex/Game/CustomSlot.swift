import Foundation

/// A user-defined daily lock slot. The six built-in slots (workout,
/// supps AM/PM, mindful, skincare AM/PM) cover the patterns we care
/// about most, but the user wants to add their own — meditation,
/// journaling, cold exposure, whatever — and have them participate in
/// `DailyLock.isComplete()` alongside the built-ins.
///
/// Custom slots are always tap-to-toggle (no separate writer surface,
/// unlike workout which is written by `commitAndDismiss` or supps which
/// are written by `StackView`'s period buttons). They render at the end
/// of the DailyLockChip after the built-ins.
struct CustomSlot: Codable, Identifiable, Hashable {
    /// Stable id. Used as the storage key prefix (`custom_<id>_<date>`)
    /// so renaming the label doesn't lose history.
    let id: String
    /// 2–5 char display label, e.g. "MED", "JRNL", "COLD".
    var label: String
    /// Full descriptive name shown in the editor sheet.
    var fullName: String
    /// Render order — lower comes first. Built-ins implicitly take
    /// orders 0–5; custom slots default to 100+.
    var order: Int

    init(id: String = UUID().uuidString,
         label: String,
         fullName: String,
         order: Int) {
        self.id = id
        self.label = label
        self.fullName = fullName
        self.order = order
    }
}

/// CRUD for the user's custom slots + per-day done state. App-Group
/// backed so widgets and intents see the same data.
enum CustomSlotStore {
    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let listKey = "custom_slots_v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.string(from: date)
    }

    private static func doneKey(slotID: String, date: Date) -> String {
        "custom_\(slotID)_\(dateKey(date))"
    }

    // MARK: - Slot list CRUD

    static func load() -> [CustomSlot] {
        guard let data = defaults.data(forKey: listKey),
              let slots = try? JSONDecoder().decode([CustomSlot].self, from: data) else {
            return []
        }
        return slots.sorted { $0.order < $1.order }
    }

    static func save(_ slots: [CustomSlot]) {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: listKey)
        NotificationCenter.default.post(name: .customSlotsDidChange, object: nil)
    }

    /// Upsert by id. Used by the editor sheet's save.
    static func upsert(_ slot: CustomSlot) {
        var slots = load()
        if let idx = slots.firstIndex(where: { $0.id == slot.id }) {
            slots[idx] = slot
        } else {
            slots.append(slot)
        }
        save(slots)
    }

    static func remove(id: String) {
        var slots = load()
        slots.removeAll { $0.id == id }
        save(slots)
    }

    // MARK: - Per-day done state

    static func isDone(slotID: String, date: Date = Date()) -> Bool {
        defaults.bool(forKey: doneKey(slotID: slotID, date: date))
    }

    static func setDone(slotID: String, _ done: Bool, date: Date = Date()) {
        let k = doneKey(slotID: slotID, date: date)
        if done {
            defaults.set(true, forKey: k)
        } else {
            defaults.removeObject(forKey: k)
        }
    }

    static func toggle(slotID: String, date: Date = Date()) {
        setDone(slotID: slotID, !isDone(slotID: slotID, date: date), date: date)
    }
}

extension Notification.Name {
    /// Fires when the user adds, removes, or renames a custom slot.
    /// DailyLockChip subscribes to refresh in place.
    static let customSlotsDidChange = Notification.Name("PrefrontalCortex.customSlotsDidChange")
}
