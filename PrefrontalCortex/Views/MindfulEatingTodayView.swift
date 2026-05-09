import SwiftUI

/// Daily intuitive-eating check-in. One tap per day; streak counted over the
/// last 7 days. Local-only state (UserDefaults), but also POSTs to the laptop
/// as a sample row so health_profile.json's "Mindful eating days/week" goal
/// can compute its `current`.
struct MindfulEatingTodayView: View {
    @State private var todayChecked: Bool = false
    @State private var streakDays: Int = 0

    private static func keyFor(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "mindful_eat_\(f.string(from: date))"
    }
    private static var todayKey: String { keyFor(Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INTUITIVE EATING")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                Text("\(streakDays)/7 this week")
                    .font(.caption2.monospaced())
                    .foregroundStyle(streakDays >= 5 ? .green : .secondary)
            }

            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: todayChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(todayChecked ? .cyan : .secondary)
                        .symbolEffect(.bounce.up, value: todayChecked)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(todayChecked ? "Today: ate mindfully" : "Did you eat mindfully today?")
                            .font(.body.italic())
                            .foregroundStyle(.white)
                        Text("hungry-when-eating · stopped when satisfied · without distraction")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(LivePressStyle())
            .sensoryFeedback(.selection, trigger: todayChecked)
            .sensoryFeedback(.success, trigger: streakDays >= 5)
        }
        .onAppear { loadState() }
    }

    // MARK: - State

    private func toggle() {
        todayChecked.toggle()
        UserDefaults.standard.set(todayChecked, forKey: Self.todayKey)
        recomputeStreak()
        Task { await syncToLaptop() }
    }

    private func loadState() {
        todayChecked = UserDefaults.standard.bool(forKey: Self.todayKey)
        recomputeStreak()
    }

    private func recomputeStreak() {
        let cal = Calendar.current
        var count = 0
        for offset in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            if UserDefaults.standard.bool(forKey: Self.keyFor(d)) {
                count += 1
            }
        }
        streakDays = count
    }

    /// Forward the daily check to the laptop as a sample so the spine can
    /// roll it up into the weekly goal `current`. Silent best-effort.
    private func syncToLaptop() async {
        guard await TransportSettings.shared.isConfigured else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let row: [String: Any] = [
            "ts": now,
            "ts_end": now,
            "source": "ios_app",
            "type": "mindful_eating",
            "value": todayChecked ? 1.0 : 0.0,
            "unit": "bool",
            "meta": "{\"via\":\"intuitive_eating_checkin\"}",
        ]
        _ = try? await TransportClient.shared.uploadSamples([row])
    }
}
