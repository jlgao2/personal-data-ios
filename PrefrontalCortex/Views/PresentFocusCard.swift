import SwiftUI

/// Hero card at the top of the Now tab. Always says "this is what to
/// think about right now" — driven by `TimeBand.current()` so the
/// content shifts as the day moves: mindful eating in the morning,
/// train at 6pm, reach out in the evening, wind down at night.
///
/// Below the headline sits a single act-of-doing affordance: StakeCard.
/// We considered an edge-note field and an "I'm in it" trembling button,
/// and cut both. The edge-note becomes journaling-as-substitute; the
/// trembling button performs presence rather than being presence
/// (Aristotle's energeia doesn't need a UI affordance to register —
/// the doing is the registration). Only the witnessed-commitment move
/// belongs here, because its outcome is the one the app can't pre-secure.
///
/// Re-renders when:
///   * The view appears (cheap fresh read).
///   * `Notification.Name.dayDidRollOver` fires (manual button + scenePhase + edge timer).
struct PresentFocusCard: View {
    let people: [SocialPerson]

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
            // The act-of-doing affordance. One — not three. The other
            // two ("I'm in it" pulse, edge-note field) were considered
            // and cut because they perform vigor rather than train it.
            // The kettlebell stays singular: a witnessed stake, lifted
            // through, the only thing in the room.
            StakeCard(band: b, people: people)
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
