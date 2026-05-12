import SwiftUI

struct GenomicsView: View {
    let genomics: Genomics

    /// Currently selected tier filter (A/B/C). nil = all visible.
    /// Tapping a TierPill toggles this; tapping the same pill again clears it.
    @State private var selectedTier: String? = nil

    private static let sourceLabels: [String: String] = [
        "pgx_quick":        "Drugs (PGx)",
        "clinvar_acmg":     "ACMG SF",
        "clinvar_full":     "ClinVar",
        "carrier_status":   "Carrier",
        "nutrition_traits": "Nutrition",
        "extra_traits":     "Extra traits",
        "imputed_panels":   "Imputed panels",
        "prs_scores":       "Polygenic risk",
    ]

    private static let sourceOrder: [String] = [
        "pgx_quick", "clinvar_acmg", "clinvar_full", "carrier_status",
        "nutrition_traits", "extra_traits", "imputed_panels", "prs_scores",
    ]

    private var sortedSources: [(key: String, rows: [Finding])] {
        let by = genomics.by_source ?? [:]
        return GenomicsView.sourceOrder
            .compactMap { key in by[key].map { (key, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GENOMICS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                if let total = genomics.total {
                    Text("\(total) findings")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                }
            }

            if let counts = genomics.tier_counts, !counts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(counts.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        TierPill(
                            tier: kv.key,
                            count: kv.value,
                            selected: selectedTier == kv.key,
                            tap: {
                                selectedTier = (selectedTier == kv.key) ? nil : kv.key
                            }
                        )
                    }
                }
            }

            VStack(spacing: 1) {
                ForEach(sortedSources, id: \.key) { entry in
                    let visibleRows = selectedTier == nil
                        ? entry.rows
                        : entry.rows.filter { $0.tier == selectedTier }
                    if !visibleRows.isEmpty {
                        GenomicsSection(
                            sourceKey: entry.key,
                            label: GenomicsView.sourceLabels[entry.key] ?? entry.key,
                            rows: visibleRows,
                            forceExpand: selectedTier != nil
                        )
                    }
                }
            }
        }
    }
}

private struct TierPill: View {
    let tier: String
    let count: Int
    let selected: Bool
    let tap: () -> Void

    private var color: Color {
        switch tier {
        case "A": return .cyan
        case "B": return .gray
        case "C": return .secondary
        default:  return .secondary
        }
    }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 4) {
                Text("Tier \(tier)")
                Text("\(count)").bold()
            }
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(selected ? Color.black : color)
            .background(selected ? color : Color.clear,
                        in: RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct GenomicsSection: View {
    let sourceKey: String
    let label: String
    let rows: [Finding]
    /// When true, the section auto-expands regardless of local toggle —
    /// used so the tier-filter pill reveals matching rows without an
    /// extra tap per section.
    var forceExpand: Bool = false

    @State private var expanded: Bool = false

    private var isExpanded: Bool { forceExpand || expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { expanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.monospaced())
                        .foregroundStyle(.cyan)
                    Text(label.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                        .tracking(2)
                    Spacer()
                    Text("\(rows.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                ForEach(rows) { row in
                    FindingRow(row: row)
                }
            }
        }
    }
}

private struct FindingRow: View {
    let row: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.gene ?? row.rsid ?? row.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.cyan)
                if let gt = row.genotype {
                    Text(gt)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let tier = row.tier {
                    Text(tier)
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(tier == "A" ? .cyan : .secondary)
                }
            }
            if let summary = row.summary {
                Text(summary)
                    .font(.footnote.italic())
                    .foregroundStyle(.white)
                    .lineLimit(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.35))
    }
}
