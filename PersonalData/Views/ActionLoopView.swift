import SwiftUI

struct ActionLoopView: View {
    let cards: [ActionCard]
    let live: [String: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTION LOOP")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            VStack(spacing: 1) {
                ForEach(cards) { card in
                    ActionCardRow(card: card, live: live[card.sample_type])
                }
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(2)
        }
    }
}

struct ActionCardRow: View {
    let card: ActionCard
    let live: Double?

    private var actual: Double? { live ?? card.latest_value }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Rectangle().fill(stateColor).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(card.gene ?? "PRS")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                    Spacer()
                    if let tier = card.finding_tier {
                        Text(tier)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if let summary = card.finding_summary {
                    Text(summary)
                        .font(.body.italic())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                if let take = card.takeaway {
                    Text(take)
                        .font(.footnote.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(actualText)
                    .font(.system(.title2, design: .serif).italic().weight(.medium))
                    .foregroundStyle(stateColor)
                Text(targetText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if live != nil {
                    Text("LIVE")
                        .font(.caption2.monospaced())
                        .tracking(1.5)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }

    private var actualText: String {
        guard let v = actual else { return "—" }
        return String(format: "%.1f", v)
    }

    private var targetText: String {
        if let t = card.target_value {
            let arrow = card.expected_direction == "increase" ? "↓" :
                        card.expected_direction == "decrease" ? "↑" : "="
            return "\(arrow) \(Int(t))"
        }
        return "conditional"
    }

    private var stateColor: Color {
        guard let actual = actual, let target = card.target_value else { return .gray }
        let ratio = actual / target
        let dir = card.expected_direction ?? "increase"
        if dir == "increase" {
            if ratio < 0.95 { return .green }
            if ratio < 1.10 { return .cyan }
            return .red
        }
        if ratio >= 1.0  { return .green }
        if ratio >= 0.85 { return .cyan }
        return .red
    }
}
