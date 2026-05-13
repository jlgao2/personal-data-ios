import SwiftUI

/// Surfaces today's Stake on the Now tab. Three states:
///
///   * No stake yet     → a single "Tell someone" button. Pressing it
///                        opens StakeSheet. Until pressed, this card is
///                        intentionally the most prominent affordance
///                        below the band hero.
///   * Stake pending/declared → renders the commitment, the witness,
///                        and the deadline countdown. Two close-out
///                        buttons appear once the deadline passes (or
///                        the user reports back early): Did / Missed.
///   * Stake resolved   → quiet acknowledgment line; the card recedes.
struct StakeCard: View {
    let band: TimeBand
    let people: [SocialPerson]

    @State private var stake: Stake?
    @State private var showStakeSheet: Bool = false
    @State private var refreshTick: Int = 0

    var body: some View {
        Group {
            if let s = stake {
                committed(s)
            } else {
                empty
            }
        }
        .id(refreshTick)
        .onAppear { stake = StakeStore.load() }
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in
            stake = StakeStore.load()
            refreshTick += 1
        }
        .sheet(isPresented: $showStakeSheet) {
            StakeSheet(people: people, band: band) { s in
                stake = s
                refreshTick += 1
            }
        }
    }

    // MARK: - Empty state — the "Tell someone" call to action.

    private var empty: some View {
        Button { showStakeSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fingers.spread")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TELL SOMEONE")
                        .font(.caption2.monospaced().bold())
                        .tracking(2)
                        .foregroundStyle(.cyan)
                    Text("Stake one act on a witness.")
                        .font(.footnote.italic())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.cyan.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.cyan.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Committed state — the live stake.

    @ViewBuilder
    private func committed(_ s: Stake) -> some View {
        let isResolved = s.status == .completed || s.status == .missed
        let pastDeadline = Date() >= s.deadline
        let color: Color = {
            switch s.status {
            case .completed: return .green
            case .missed:    return .orange
            default:         return .cyan
            }
        }()

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("STAKE")
                    .font(.caption2.monospaced().bold())
                    .tracking(2)
                    .foregroundStyle(color)
                Spacer()
                Text(s.status.rawValue.uppercased())
                    .font(.caption2.monospaced())
                    .tracking(1.5)
                    .foregroundStyle(color.opacity(0.75))
            }
            Text(s.prompt)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .strikethrough(isResolved, color: .white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text("Witness: \(s.witnessName)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(deadlineLabel(s.deadline))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.55))
            }
            if !isResolved && pastDeadline {
                HStack(spacing: 8) {
                    Button("Did it") { resolve(s, status: .completed) }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    Button("Missed") { resolve(s, status: .missed) }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    Spacer()
                }
                .controlSize(.small)
                .padding(.top, 4)
            } else if !isResolved {
                Button("Tell them now") { resolve(s, status: .completed) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(color)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color.opacity(isResolved ? 0.25 : 0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(isResolved ? 0.7 : 1.0)
    }

    private func resolve(_ s: Stake, status: Stake.Status) {
        var updated = s
        updated.status = status
        updated.resolvedAt = Date()
        StakeStore.save(updated)
        stake = updated
        refreshTick += 1
    }

    private func deadlineLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "by \(f.string(from: d))"
    }
}
