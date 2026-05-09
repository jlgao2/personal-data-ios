import SwiftUI

/// Center-screen toast shown when one or more achievements unlock.
/// Iterates through new unlocks one at a time, ~2 s each, with a soft bounce.
struct AchievementUnlockToast: View {

    @Binding var pending: [Achievement]
    @State private var visible: Achievement? = nil

    var body: some View {
        ZStack {
            if let ach = visible {
                VStack(spacing: 8) {
                    Image(systemName: ach.icon)
                        .font(.largeTitle)
                        .foregroundStyle(.cyan)
                        .symbolEffect(.bounce, value: ach.id)
                    Text(ach.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                    Text("ACHIEVEMENT UNLOCKED")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                        .tracking(2)
                }
                .padding(20)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.cyan.opacity(0.3)))
                .shadow(color: Color.cyan.opacity(0.25), radius: 18)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .onTapGesture { visible = nil }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: visible?.id)
        .task(id: pending.count) {
            await drainQueue()
        }
    }

    private func drainQueue() async {
        while !pending.isEmpty {
            let next = pending.removeFirst()
            withAnimation { visible = next }
            try? await Task.sleep(for: .seconds(2.0))
            withAnimation { visible = nil }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
