import SwiftUI

/// Shown over the wheel during the midnight rollover. Summarises the
/// day that just closed and, if the workout never got reconciled,
/// asks one last time before the fresh day.
struct DayCloseView: View {
    let rhythm: DayRhythm          // built with the CLOSING day's date, closing: true
    var onDismiss: () -> Void

    var body: some View {
        let s = rhythm.closeSummary()
        VStack(alignment: .leading, spacing: 16) {
            Text("DAY CLOSED")
                .font(.caption2.monospaced().bold()).tracking(2)
                .foregroundStyle(.cyan)
            Text("\(s.resolved)/\(s.resolved + s.unresolved) resolved")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
            FlowList(items: s.slots)

            if rhythm.escalation == .closing {
                Text("What did you do today?")
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
                WorkoutReconcileRow(onResolved: onDismiss)
            }

            Button(action: onDismiss) {
                Text("Start fresh →")
                    .font(.callout.monospaced().bold())
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.cyan.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
        .transition(.opacity)
    }

    private struct FlowList: View {
        let items: [(label: String, done: Bool)]
        var body: some View {
            HStack(spacing: 8) {
                ForEach(items, id: \.label) { it in
                    Text(it.label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(it.done ? .cyan : .white.opacity(0.35))
                }
            }
        }
    }
}

/// Inline workout reconcile — shared by the Now-tab workout card and
/// DayCloseView. One tap each; "Else" reveals a compact sport pick.
struct WorkoutReconcileRow: View {
    var onResolved: () -> Void
    @State private var picking = false

    private let sports = ["Cycling","Running","Strength","Yoga","Swimming","Walk"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                recBtn("✓ Did it") { WorkoutReconcile.didIt(); onResolved() }
                recBtn("⤴ Else")   { picking.toggle() }
                recBtn("○ Rest")   { WorkoutReconcile.didRest(); onResolved() }
                recBtn("⊘ Skip")   { WorkoutReconcile.skip(reason: "busy"); onResolved() }
            }
            if picking {
                HStack(spacing: 8) {
                    ForEach(sports, id: \.self) { sp in
                        Button(sp) { WorkoutReconcile.didElse(sport: sp); onResolved() }
                            .font(.caption2.monospaced())
                            .foregroundStyle(.cyan)
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.cyan.opacity(0.4), lineWidth: 1))
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    @ViewBuilder private func recBtn(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.caption.monospaced().bold())
                .foregroundStyle(.cyan)
                .padding(.vertical, 8).padding(.horizontal, 10)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.cyan.opacity(0.45), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
