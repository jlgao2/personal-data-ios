import SwiftUI

/// "TODAY'S SESSIONS" section card on the Now tab. One row per HK/Garmin
/// workout that landed today, surfaced so the user can confirm at a glance
/// that the cycle/run/etc. was picked up — without digging into a sheet.
///
/// Sits next to `AdaptedSessionView` so today's *actual* sessions are
/// visually grouped with today's *prescribed* session.
///
/// Data source: `DeviationStore.todayWorkouts()`, populated by:
///   * `AppStore.pullHealthKitWorkouts` (local-first, from HK on phone)
///   * `AppStore.refreshAlternateHistory` (bundle-derived, only when non-empty)
///
/// (Name retained for ContentView call-site stability. Reads as
/// "TodaysSessionsView" — the "Chip" suffix is historical.)
struct TodaysWorkoutChip: View {

    /// Bumped by `.onAppear` to force a re-read after the AppStore refreshes
    /// the App-Group store on foreground. Same idiom as `DailyLockChip`.
    @State private var refreshTick: Int = 0

    private var rows: [DeviationStore.TodayWorkout] {
        DeviationStore.todayWorkouts()
    }

    var body: some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S SESSIONS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                VStack(spacing: 1) {
                    ForEach(rows, id: \.sport) { w in
                        sessionRow(w)
                    }
                }
                .background(Color.white.opacity(0.05))
            }
            .id(refreshTick)
            .onAppear { refreshTick += 1 }
        }
    }

    @ViewBuilder
    private func sessionRow(_ w: DeviationStore.TodayWorkout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(w.sport.uppercased())
                .font(.callout.monospaced().weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.cyan)
            Spacer()
            Text("\(w.durationMin) MIN")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.85))
                .tracking(1.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }
}
