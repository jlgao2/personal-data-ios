import SwiftUI

/// Now-tab stack: two big organic buttons — "Took morning" and "Took evening".
/// Each toggles in one tap; per-day state in UserDefaults so it resets at
/// midnight. The detailed per-supplement breakdown lives in StackDetailView
/// on the Plan tab.
struct StackView: View {
    let items: [Supplement]
    @State private var morningDone: Bool = false
    @State private var eveningDone: Bool = false

    private var morningSupps: [Supplement] {
        items.filter { !Self.isEvening($0.timing) }
    }
    private var eveningSupps: [Supplement] {
        items.filter { Self.isEvening($0.timing) }
    }

    static func isEvening(_ timing: String?) -> Bool {
        let t = (timing ?? "").lowercased()
        return t.contains("evening") || t.contains("before bed") || t.contains("night")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STACK")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                Text(progressLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if !morningSupps.isEmpty {
                    PeriodButton(
                        label: "MORNING",
                        count: morningSupps.count,
                        checked: morningDone,
                        glowColor: .yellow,
                        onTap: { toggle(period: .morning) }
                    )
                }
                if !eveningSupps.isEmpty {
                    PeriodButton(
                        label: "EVENING",
                        count: eveningSupps.count,
                        checked: eveningDone,
                        glowColor: .indigo,
                        onTap: { toggle(period: .evening) }
                    )
                }
            }
        }
        .onAppear { loadState() }
    }

    // MARK: - State

    private enum Period: String { case morning, evening }

    private var progressLabel: String {
        let done = (morningDone ? morningSupps.count : 0) +
                   (eveningDone ? eveningSupps.count : 0)
        return "\(done)/\(items.count)"
    }

    private static func key(_ p: Period) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "stack_period_\(f.string(from: Date()))_\(p.rawValue)"
    }

    private func toggle(period: Period) {
        switch period {
        case .morning: morningDone.toggle()
                       UserDefaults.standard.set(morningDone, forKey: Self.key(.morning))
        case .evening: eveningDone.toggle()
                       UserDefaults.standard.set(eveningDone, forKey: Self.key(.evening))
        }
    }

    private func loadState() {
        morningDone = UserDefaults.standard.bool(forKey: Self.key(.morning))
        eveningDone = UserDefaults.standard.bool(forKey: Self.key(.evening))
    }
}

// MARK: - Period button (the actual touch target)

private struct PeriodButton: View {
    let label: String
    let count: Int
    let checked: Bool
    let glowColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(checked ? glowColor : .secondary)
                    .symbolEffect(.bounce.up, value: checked)
                Text(label)
                    .font(.caption2.monospaced().bold())
                    .tracking(2)
                    .foregroundStyle(checked ? glowColor : .white.opacity(0.65))
                Text("\(count) supp\(count == 1 ? "" : "s")")
                    .font(.caption2.italic())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(checked ? glowColor.opacity(0.10) : Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(checked ? glowColor.opacity(0.45)
                                          : Color.white.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: checked ? glowColor.opacity(0.25) : .clear,
                    radius: 12, x: 0, y: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(LivePressStyle())
        .sensoryFeedback(.selection, trigger: checked)
    }
}

// MARK: - Detailed list (Plan tab)

/// Full breakdown of the supplement stack — what's in it, dose, rationale.
/// Lives on the Plan tab; informational, no checkboxes (those are on Now).
struct StackDetailView: View {
    let items: [Supplement]

    private var morning: [Supplement] {
        items.filter { !StackView.isEvening($0.timing) }
    }
    private var evening: [Supplement] {
        items.filter { StackView.isEvening($0.timing) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STACK DETAIL")
                .font(.caption2.monospaced())
                .foregroundStyle(.cyan)
                .tracking(2)
            if !morning.isEmpty {
                section("MORNING", supps: morning, glow: .yellow)
            }
            if !evening.isEmpty {
                section("EVENING", supps: evening, glow: .indigo)
            }
        }
    }

    private func section(_ title: String, supps: [Supplement], glow: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption2.monospaced())
                    .foregroundStyle(glow)
                    .tracking(2)
                Spacer()
                Text(supps.contains(where: { $0.with_food == true }) ? "with food" : "fasted")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(supps) { s in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.name)
                            .font(.body.italic())
                            .foregroundStyle(s.evidence == "strong" ? .white : .gray)
                        Spacer()
                        if let dose = s.dose {
                            Text(dose)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.cyan)
                        }
                    }
                    if let r = s.rationale {
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
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glow.opacity(0.18))
        }
    }
}
