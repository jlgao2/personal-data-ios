import SwiftUI

/// Big chip on the Profile tab. Shows current streak + longest-ever +
/// (if streak == 0 and we have history) the "starting over · N days
/// was your last run" nudge.
struct StreakChip: View {

    @State private var refreshTick: Int = 0
    private var state: StreakState { StreakState.load() }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.cyan.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "flame")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                    .symbolEffect(.bounce, value: state.current)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.current) day streak")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                if state.current == 0, state.lastCompleteDate != nil, state.longest > 0 {
                    Text("starting over · \(state.longest) days was your last run")
                        .font(.caption2.italic())
                        .foregroundStyle(.secondary)
                } else {
                    Text("best: \(state.longest)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.18)))
        .id(refreshTick)
        .onAppear { refreshTick += 1 }
    }
}
