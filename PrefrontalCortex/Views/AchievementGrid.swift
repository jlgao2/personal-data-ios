import SwiftUI

/// 4-column grid of achievement icons. Locked = grey + outlined; unlocked =
/// cyan + filled. Tap any cell → small detail sheet with name, description,
/// and unlock date if applicable.
struct AchievementGrid: View {

    @State private var selected: Achievement? = nil
    private var state: Achievements.State { Achievements.load() }

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACHIEVEMENTS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                Text("\(state.unlocked.count)/\(Achievements.all.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Achievements.all) { ach in
                    let unlocked = state.unlocked[ach.id] != nil
                    Button { selected = ach } label: {
                        VStack(spacing: 4) {
                            Image(systemName: ach.icon)
                                .font(.title3)
                                .foregroundStyle(unlocked ? .cyan : .white.opacity(0.25))
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(unlocked ? Color.cyan.opacity(0.15)
                                                       : Color.white.opacity(0.03))
                                )
                                .overlay(Circle().strokeBorder(
                                    unlocked ? Color.cyan.opacity(0.4)
                                             : Color.white.opacity(0.10), lineWidth: 1))
                        }
                    }
                    .buttonStyle(LivePressStyle())
                }
            }
        }
        .sheet(item: $selected) { ach in
            AchievementDetailSheet(achievement: ach,
                                   unlockDate: state.unlocked[ach.id])
                .presentationDetents([.medium])
        }
    }
}

private struct AchievementDetailSheet: View {
    let achievement: Achievement
    let unlockDate: String?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.cyan.opacity(unlockDate != nil ? 0.18 : 0.05))
                    .frame(width: 80, height: 80)
                Image(systemName: achievement.icon)
                    .font(.largeTitle)
                    .foregroundStyle(unlockDate != nil ? .cyan : .white.opacity(0.3))
            }
            Text(achievement.name)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
            Text(achievement.description)
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let unlockDate {
                Text("Unlocked \(unlockDate)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
            } else {
                Text("locked")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
            }
            Spacer()
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
