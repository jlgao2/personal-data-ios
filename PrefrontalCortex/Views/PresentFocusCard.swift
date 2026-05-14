import SwiftUI

/// Hero card at the top of the Now tab. Always says "this is what to
/// think about right now" — driven by `TimeBand.current()` so the
/// content shifts as the day moves: mindful eating in the morning,
/// train at 6pm, reach out in the evening, wind down at night.
///
/// The hero card is the band headline, subtitle, and accent. Earlier
/// iterations bolted on a "Stake" affordance (commit an act to a
/// witness via share sheet) but that's been pulled — the structural
/// commitment-to-a-witness pattern moved out to a separate app
/// (Loosen) where the daily knot-rotation gives it the right home.
/// What remains here is just the present-focus reminder: this band,
/// this headline, this is what to think about right now.
///
/// Re-renders when:
///   * The view appears (cheap fresh read).
///   * `Notification.Name.dayDidRollOver` fires (manual button + scenePhase + edge timer).
struct PresentFocusCard: View {
    @State private var band: TimeBand = .current()
    @State private var refreshTick: Int = 0

    var body: some View {
        let b = band
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(b.tag)
                        .font(.caption2.monospaced().bold())
                        .tracking(2)
                        .foregroundStyle(b.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(b.accent.opacity(0.6), lineWidth: 1))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: b.symbol)
                        .font(.title3)
                        .foregroundStyle(b.accent.opacity(0.85))
                }
                Text(b.headline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(b.subtitle)
                    .font(.footnote.italic())
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(b.accent.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .id(refreshTick)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in
            refresh()
        }
    }

    private func refresh() {
        band = .current()
        refreshTick += 1
    }
}
