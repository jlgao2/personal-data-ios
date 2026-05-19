import Foundation
import UserNotifications

/// Local-notification engine. On every refresh we compute each Action Loop card's
/// state (ok / drift / off / none) and compare against the previous state stored in
/// @AppStorage. When a card flips into "drift" or "off", we schedule a local
/// notification so the user gets pinged instead of having to open the app.
enum CardState: String, Codable {
    case ok      // within target
    case drift   // 5-15% off
    case off     // > 15% off
    case none    // missing data
}

func computeCardState(actual: Double?, target: Double?, direction: String?) -> CardState {
    guard let actual, let target, target != 0 else { return .none }
    let ratio = actual / target
    let dir = direction ?? "increase"
    if dir == "increase" {
        if ratio < 0.95 { return .ok }
        if ratio < 1.10 { return .drift }
        return .off
    }
    if ratio >= 1.0  { return .ok }
    if ratio >= 0.85 { return .drift }
    return .off
}

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let stateKey = "card_states_v1"

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Compare current card states against persisted ones; fire notifications for
    /// any card that newly crossed into drift/off (not for cards that improved).
    /// Returns the notifications fired.
    func diffAndNotify(cards: [ActionCard], live: [String: Double]) async -> [String] {
        let previous = loadStates()
        var current: [String: CardState] = [:]
        var fired: [String] = []

        for card in cards {
            let actual = live[card.sample_type] ?? card.latest_value
            let state  = computeCardState(actual: actual,
                                          target: card.target_value,
                                          direction: card.expected_direction)
            current[card.id] = state

            let prev = previous[card.id] ?? .none
            let regressed = (prev == .ok    && (state == .drift || state == .off)) ||
                            (prev == .drift && state == .off)
            if regressed {
                let title = (card.gene ?? "PRS") + " · " + card.sample_type.replacingOccurrences(of: "_", with: " ")
                let body  = body(for: card, actual: actual, state: state)
                await scheduleNotification(id: card.id, title: title, body: body)
                fired.append(card.id)
            }
        }

        saveStates(current)
        return fired
    }

    private func body(for card: ActionCard, actual: Double?, state: CardState) -> String {
        let actualStr = actual.map { String(format: "%.1f", $0) } ?? "—"
        let targetStr = card.target_value.map { String(format: "%g", $0) } ?? "?"
        let arrow = state == .off ? "off-target" : "drifting"
        return "\(actualStr) vs target \(targetStr) — \(arrow). \(card.takeaway ?? "")"
    }

    private func scheduleNotification(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        // Fire in 5 seconds for testing; production use can use a UNCalendarNotificationTrigger.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func loadStates() -> [String: CardState] {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let map = try? JSONDecoder().decode([String: CardState].self, from: data) else {
            return [:]
        }
        return map
    }

    private func saveStates(_ states: [String: CardState]) {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    private static let group = "group.com.jlgao.PrefrontalCortex"
    private static func nudgeKey(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "en_US_POSIX")
        return "workout_nudge_\(f.string(from: d))"
    }
    private let nudgeID = "workout-nudge"

    /// Schedule ONE "what did you do?" notification at the night-band
    /// start (22:00) if the workout is still unresolved. Idempotent per
    /// day (a dated app-group flag). Cancels if already resolved.
    /// .timeSensitive interruption pierces Focus / Do Not Disturb.
    func syncWorkoutNudge() {
        let ud = UserDefaults(suiteName: Self.group) ?? .standard
        let rhythm = DayRhythm()
        if rhythm.workoutResolved {
            center.removePendingNotificationRequests(withIdentifiers: [nudgeID])
            return
        }
        let key = Self.nudgeKey()
        if ud.bool(forKey: key) { return }
        let cal = Calendar.current
        var c = cal.dateComponents([.year,.month,.day], from: Date())
        c.hour = 22; c.minute = 0
        guard let fire = cal.date(from: c), fire > Date() else { return }
        ud.set(true, forKey: key)
        let content = UNMutableNotificationContent()
        content.title = "What did you do today?"
        content.body  = "Tap to log your workout — or mark rest."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trig = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year,.month,.day,.hour,.minute], from: fire),
            repeats: false)
        center.add(UNNotificationRequest(identifier: nudgeID, content: content, trigger: trig))
    }

    func cancelWorkoutNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [nudgeID])
    }
}
