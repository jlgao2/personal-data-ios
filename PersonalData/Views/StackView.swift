import SwiftUI

struct StackView: View {
    let items: [Supplement]

    private static let timingOrder = [
        "morning", "30-60 min pre-workout", "with lunch",
        "afternoon", "evening", "before bed"
    ]

    private var grouped: [(timing: String, supps: [Supplement])] {
        var byTiming: [String: [Supplement]] = [:]
        for s in items {
            let t = s.timing ?? "unscheduled"
            byTiming[t, default: []].append(s)
        }
        return byTiming.keys.sorted { a, b in
            let ai = StackView.timingOrder.firstIndex(of: a) ?? 99
            let bi = StackView.timingOrder.firstIndex(of: b) ?? 99
            return ai < bi
        }.map { ($0, byTiming[$0]!) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STACK")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            VStack(spacing: 1) {
                ForEach(grouped, id: \.timing) { group in
                    StackGroupView(timing: group.timing, items: group.supps)
                }
            }
        }
    }
}

private struct StackGroupView: View {
    let timing: String
    let items: [Supplement]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timing.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                Text(items.contains(where: { $0.with_food == true }) ? "with food" : "fasted")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name)
                            .font(.body.italic())
                            .foregroundStyle(item.evidence == "strong" ? .white : .gray)
                            .fontWeight(item.evidence == "strong" ? .medium : .regular)
                        Spacer()
                        if let dose = item.dose {
                            Text(dose)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.cyan)
                        }
                    }
                    if let r = item.rationale {
                        Text(r)
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.vertical, 4)
                Divider().background(Color.white.opacity(0.05))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
    }
}
