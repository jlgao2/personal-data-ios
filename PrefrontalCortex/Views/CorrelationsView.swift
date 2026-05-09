import SwiftUI

/// Cross-source correlation findings — the data-driven rules' grounding.
/// Mirrors the web dashboard's Correlations panel.
struct CorrelationsView: View {
    let findings: [CorrelationFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CORRELATIONS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                Text("cross-source patterns")
                    .font(.caption2.italic())
                    .foregroundStyle(.secondary)
            }

            if findings.isEmpty {
                Text("No correlations yet — need ≥30 days of data.")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(findings) { f in
                        CorrelationCard(finding: f)
                    }
                }
            }
        }
    }
}

private struct CorrelationCard: View {
    let finding: CorrelationFinding

    private var trendColor: Color {
        switch finding.trend.lowercased() {
        case "positive": return .green
        case "negative": return .red
        default:         return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(finding.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer()
                Text(finding.trend.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(trendColor)
                    .tracking(1.5)
            }

            if let table = finding.table, !table.isEmpty {
                SportDeltaTable(rows: table)
            } else if let summary = finding.summary {
                Text(summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action = finding.actionable, !action.isEmpty {
                Text(action)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text("n = \(finding.n)")
                if let r = finding.r {
                    Text("·")
                    Text(String(format: "r = %@%.2f", r >= 0 ? "+" : "", r))
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(trendColor.opacity(0.25))
        )
    }
}

private struct SportDeltaTable: View {
    let rows: [SportDelta]

    private var maxAbsDelta: Double {
        rows.map { abs($0.delta_rhr) }.max() ?? 1
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Text(row.sport.replacingOccurrences(of: "_", with: " ").lowercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    deltaBar(for: row)
                    Text(String(format: "%+.1f", row.delta_rhr))
                        .font(.caption2.monospaced())
                        .foregroundStyle(deltaColor(row.delta_rhr))
                        .frame(width: 40, alignment: .trailing)
                    Text("n=\(row.n)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func deltaColor(_ d: Double) -> Color {
        if d > 1 { return .red }
        if d > 0 { return .orange }
        if d > -1 { return .secondary }
        return .green
    }

    private func deltaBar(for row: SportDelta) -> some View {
        GeometryReader { geo in
            let total = geo.size.width
            let mid = total / 2
            let frac = min(1.0, abs(row.delta_rhr) / max(maxAbsDelta, 0.01))
            let width = mid * frac
            let xStart = row.delta_rhr >= 0 ? mid : mid - width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                Rectangle()
                    .fill(deltaColor(row.delta_rhr).opacity(0.6))
                    .frame(width: width)
                    .offset(x: xStart)
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 12)
                    .offset(x: mid - 0.5, y: 0)
            }
        }
        .frame(height: 12)
    }
}
