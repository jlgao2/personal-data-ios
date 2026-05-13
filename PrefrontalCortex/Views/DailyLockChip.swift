import SwiftUI

/// Now-tab indicator. One dot per *self-authored* daily slot: workout,
/// AM supps, PM supps, mindful eating, skincare AM, skincare PM. Slots
/// tagged outside (via long-press on the corresponding obligation card)
/// exit the chip entirely — both numerator and denominator shrink so
/// the progress capsule reflects only what the user actually authored.
/// Skincare slots tap-to-toggle directly here (no other UI marks them
/// done); the rest are written by their respective surfaces.
///
/// Refresh triggers:
///   * `.onAppear` (cheap fresh read on tab open)
///   * `.dayDidRollOver` (manual button + scenePhase + edge timer)
///   * `.authorshipDidChange` (a slot was retagged self/outside)
struct DailyLockChip: View {

    @State private var refreshTick: Int = 0

    /// Pairs of (slot, surface). Slot is rendered only when the surface
    /// isn't outside-tagged. Order is deliberate — the user's expected
    /// reading flow across the day.
    private struct Slot {
        let label: String
        let surface: AuthorshipSurface
        let done: () -> Bool
        let toggle: (() -> Void)?
    }

    private var slots: [Slot] {
        [
            Slot(label: "W",     surface: .workout,    done: DailyLock.isWorkoutDone,       toggle: nil),
            Slot(label: "AM",    surface: .suppsAM,    done: DailyLock.isAMSuppsDone,       toggle: nil),
            Slot(label: "PM",    surface: .suppsPM,    done: DailyLock.isPMSuppsDone,       toggle: nil),
            Slot(label: "M",     surface: .mindful,    done: DailyLock.isMindfulEatingDone, toggle: nil),
            Slot(label: "SK·AM", surface: .skincareAM, done: DailyLock.isSkincareAMDone,
                 toggle: { DailyLock.setSkincareAMDone(!DailyLock.isSkincareAMDone()) }),
            Slot(label: "SK·PM", surface: .skincarePM, done: DailyLock.isSkincarePMDone,
                 toggle: { DailyLock.setSkincarePMDone(!DailyLock.isSkincarePMDone()) }),
        ]
    }

    private var visibleSlots: [Slot] {
        slots.filter { AuthorshipStore.get($0.surface) != .outside }
    }

    private var doneCount: Int {
        visibleSlots.filter { $0.done() }.count
    }

    private var streak: Int { StreakState.load().current }

    var body: some View {
        let visible = visibleSlots
        let total = max(1, visible.count)  // avoid /0 if user tagged everything outside
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ForEach(0..<visible.count, id: \.self) { i in
                    let s = visible[i]
                    slot(filled: s.done(), label: s.label, toggle: s.toggle.map { action in
                        { action(); refreshTick += 1 }
                    })
                }
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
                        .frame(width: geo.size.width * CGFloat(doneCount) / CGFloat(total), height: 2)
                }
            }
            .frame(height: 2)
        }
        .id(refreshTick)
        .onAppear { refreshTick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in
            refreshTick += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .authorshipDidChange)) { _ in
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
