import SwiftUI

/// Now-tab indicator. Built-in slots first (workout, AM supps, PM supps,
/// mindful eating, skincare AM, skincare PM), then any user-defined
/// custom slots. Slots tagged outside (via long-press on the
/// corresponding obligation card) exit the chip; the progress capsule
/// reflects only what the user authored.
///
/// Long-press the whole chip → CustomSlotEditorSheet (add/rename/remove
/// custom slots). Tap a skincare or custom dot to toggle done state.
struct DailyLockChip: View {

    @State private var refreshTick: Int = 0
    @State private var celebrate = 0   // bumped once when the day first fills
    @State private var showEditor: Bool = false

    private static let group = "group.com.jlgao.PrefrontalCortex"
    private static func celebratedKey(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "en_US_POSIX")
        return "day_celebrated_\(f.string(from: d))"
    }
    private func fireBeatIfNewlyComplete() {
        let ud = UserDefaults(suiteName: Self.group) ?? .standard
        let key = Self.celebratedKey()
        let slots = DailyLockSlots.visible()
        guard !slots.isEmpty, slots.allSatisfy({ $0.done }),
              !ud.bool(forKey: key) else { return }
        ud.set(true, forKey: key)
        celebrate += 1
    }

    private var doneCount: Int { DailyLockSlots.visible().filter { $0.done }.count }
    private var streak: Int { StreakState.load().current }

    var body: some View {
        let visible = DailyLockSlots.visible()
        let total = max(1, visible.count)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ForEach(visible) { s in
                    slot(filled: s.done, label: s.label, toggle: s.toggle.map { action in
                        { action(); refreshTick += 1; fireBeatIfNewlyComplete() }
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
                        .frame(width: geo.size.width * CGFloat(doneCount) / CGFloat(total),
                               height: 2)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8),
                                   value: doneCount)
                }
            }
            .frame(height: 2)
            .overlay(alignment: .trailing) {
                if celebrate > 0 {
                    Text("Day complete")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(.cyan)
                        .transition(.opacity)
                }
            }
            .sensoryFeedback(.success, trigger: celebrate)
            .animation(.easeOut(duration: 0.3), value: celebrate)
        }
        .contentShape(Rectangle())   // make the empty area long-pressable too
        .onLongPressGesture(minimumDuration: 0.5) {
            showEditor = true
        }
        .id(refreshTick)
        .onAppear { refreshTick += 1; fireBeatIfNewlyComplete() }
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in
            refreshTick += 1; fireBeatIfNewlyComplete()
        }
        .onReceive(NotificationCenter.default.publisher(for: .authorshipDidChange)) { _ in
            refreshTick += 1; fireBeatIfNewlyComplete()
        }
        .onReceive(NotificationCenter.default.publisher(for: .customSlotsDidChange)) { _ in
            refreshTick += 1; fireBeatIfNewlyComplete()
        }
        .sheet(isPresented: $showEditor) {
            CustomSlotEditorSheet()
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
