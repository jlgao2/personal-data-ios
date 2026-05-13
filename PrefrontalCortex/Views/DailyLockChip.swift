import SwiftUI

/// Six-dot Now-tab indicator: workout · AM supps · PM supps · mindful eating
/// · skincare AM · skincare PM. Each dot fills cyan when its slot is complete.
/// Skincare slots tap-to-toggle directly here (no other UI marks them done);
/// the other four are written by their respective surfaces (workout commit,
/// stack check-off, mindful-eat acknowledge).
///
/// A thin progress line behind the dots fills 0→1 with the count of completed
/// slots. If today's complete streak ≥ 7, a small "N days running" caption
/// appears below.
struct DailyLockChip: View {

    @State private var refreshTick: Int = 0

    private var workoutDone:  Bool { DailyLock.isWorkoutDone() }
    private var amDone:       Bool { DailyLock.isAMSuppsDone() }
    private var pmDone:       Bool { DailyLock.isPMSuppsDone() }
    private var mindfulDone:  Bool { DailyLock.isMindfulEatingDone() }
    private var skinAMDone:   Bool { DailyLock.isSkincareAMDone() }
    private var skinPMDone:   Bool { DailyLock.isSkincarePMDone() }
    private var doneCount:    Int  {
        [workoutDone, amDone, pmDone, mindfulDone, skinAMDone, skinPMDone].filter { $0 }.count
    }
    private static let slotTotal: CGFloat = 6
    private var streak: Int { StreakState.load().current }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                slot(filled: workoutDone, label: "W")
                slot(filled: amDone,      label: "AM")
                slot(filled: pmDone,      label: "PM")
                slot(filled: mindfulDone, label: "M")
                slot(
                    filled: skinAMDone,
                    label: "SK·AM",
                    toggle: { DailyLock.setSkincareAMDone(!skinAMDone); refreshTick += 1 }
                )
                slot(
                    filled: skinPMDone,
                    label: "SK·PM",
                    toggle: { DailyLock.setSkincarePMDone(!skinPMDone); refreshTick += 1 }
                )
                Spacer()
                if streak >= 7 {
                    Text("\(streak)d running")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05)).frame(height: 2)
                    Capsule()
                        .fill(Color.cyan.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(doneCount) / Self.slotTotal, height: 2)
                }
            }
            .frame(height: 2)
        }
        .id(refreshTick)
        .onAppear { refreshTick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in
            refreshTick += 1
        }
    }

    @ViewBuilder
    private func slot(filled: Bool, label: String, toggle: (() -> Void)? = nil) -> some View {
        let dot = VStack(spacing: 2) {
            Circle()
                .fill(filled ? Color.cyan : Color.white.opacity(0.12))
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(filled ? Color.cyan : Color.white.opacity(0.2), lineWidth: 1))
                .symbolEffect(.bounce.up, value: filled)
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(filled ? .cyan : .secondary)
                .tracking(1)
        }
        if let toggle {
            Button(action: toggle) { dot }
                .buttonStyle(.plain)
        } else {
            dot
        }
    }
}
