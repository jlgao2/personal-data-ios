import SwiftUI

/// Rendered in place of `PresentFocusCard` when there's nothing live
/// to act on — no stake committed today, no self-authored obligation
/// pending for the current band. Refuses to entertain. Refuses to
/// substitute charts for action.
///
/// Tone — this is the *kettlebell at rest*, not the app receding.
/// The app is a PFC trainer; the trainer doesn't disappear when you
/// stop lifting, it sits there waiting until you pick it back up.
/// So the copy names that explicitly: "Not training right now."
struct EmptyHero: View {
    let band: TimeBand

    @State private var refreshTick: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(band.tag)
                    .font(.caption2.monospaced().bold())
                    .tracking(2)
                    .foregroundStyle(band.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(band.accent.opacity(0.6), lineWidth: 1))
                    .clipShape(Capsule())
                Spacer()
                Text("AT REST")
                    .font(.caption2.monospaced())
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text(band.headline)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Not training right now. The work is on the other side of a stake.")
                .font(.body.italic())
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)
            Text("Stake something to begin. Close the app to act.")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(Color.black.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(band.accent.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .id(refreshTick)
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in
            refreshTick += 1
        }
    }
}

/// Centralised decision: is the Now tab in "at rest" mode?
/// Returns true when no pending self-authored obligation exists for
/// the current band. (Earlier versions also checked StakeStore; the
/// Stake feature has been removed and that part of the gate is
/// retired.)
///
/// Otherwise the standard layout (PresentFocusCard) renders.
enum EmptyHeroGate {
    static func shouldRender(now: Date = Date()) -> Bool {
        if hasPendingSelfAuthored(for: TimeBand.current(at: now)) {
            return false
        }
        return true
    }

    private static func hasPendingSelfAuthored(for band: TimeBand) -> Bool {
        switch band {
        case .morning:
            return pending(.suppsAM, gate: !DailyLock.isAMSuppsDone())
                || pending(.mindful, gate: !DailyLock.isMindfulEatingDone())
                || pending(.skincareAM, gate: !DailyLock.isSkincareAMDone())
        case .midday:
            return pending(.mindful, gate: !DailyLock.isMindfulEatingDone())
        case .workout:
            return pending(.workout, gate: !DailyLock.isWorkoutDone())
        case .reachOut:
            return false
        case .night:
            return pending(.suppsPM, gate: !DailyLock.isPMSuppsDone())
                || pending(.skincarePM, gate: !DailyLock.isSkincarePMDone())
        }
    }

    /// Pending here means: the slot isn't done AND the surface is
    /// self-authored (or unset — default-author-yours; the explicit
    /// untag is the user saying "this isn't mine").
    private static func pending(_ surface: AuthorshipSurface, gate: Bool) -> Bool {
        guard gate else { return false }
        let a = AuthorshipStore.get(surface)
        return a == .selfAuthored || a == .unset
    }
}
