import SwiftUI

/// Two-block daily checklist: MORNING (everything that's not "evening" or
/// "before bed") + EVENING. Tap rows to check; state lives in UserDefaults
/// keyed by today's date so it resets at midnight.
struct StackView: View {
    let items: [Supplement]
    @State private var checks: [String: Bool] = [:]

    private var morningSupps: [Supplement] {
        items.filter { !Self.isEvening($0.timing) }
    }
    private var eveningSupps: [Supplement] {
        items.filter { Self.isEvening($0.timing) }
    }

    private static func isEvening(_ timing: String?) -> Bool {
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

            VStack(spacing: 8) {
                if !morningSupps.isEmpty {
                    StackChecklistGroup(label: "MORNING", supps: morningSupps,
                                        checks: $checks, onToggle: toggle)
                }
                if !eveningSupps.isEmpty {
                    StackChecklistGroup(label: "EVENING", supps: eveningSupps,
                                        checks: $checks, onToggle: toggle)
                }
            }
        }
        .onAppear { loadChecks() }
    }

    private var progressLabel: String {
        let done = items.filter { checks[$0.name] ?? false }.count
        return "\(done) / \(items.count)"
    }

    // MARK: - Per-day persistence

    private static func todayKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "stack_check_\(f.string(from: Date()))"
    }

    private func loadChecks() {
        if let data = UserDefaults.standard.data(forKey: Self.todayKey()),
           let dict = try? JSONDecoder().decode([String: Bool].self, from: data) {
            checks = dict
        } else {
            checks = [:]
        }
    }

    private func toggle(_ name: String) {
        checks[name, default: false].toggle()
        if let data = try? JSONEncoder().encode(checks) {
            UserDefaults.standard.set(data, forKey: Self.todayKey())
        }
    }
}

private struct StackChecklistGroup: View {
    let label: String
    let supps: [Supplement]
    @Binding var checks: [String: Bool]
    let onToggle: (String) -> Void

    private var doneCount: Int {
        supps.filter { checks[$0.name] ?? false }.count
    }
    private var withFood: Bool {
        supps.contains(where: { $0.with_food == true })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                Text("\(doneCount)/\(supps.count) · \(withFood ? "with food" : "fasted")")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(supps) { s in
                StackChecklistRow(
                    supp: s,
                    checked: checks[s.name] ?? false,
                    onTap: { onToggle(s.name) }
                )
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct StackChecklistRow: View {
    let supp: Supplement
    let checked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(checked ? .cyan : .secondary)
                    .symbolEffect(.bounce.up, value: checked)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(supp.name)
                            .font(.body.italic())
                            .foregroundStyle(checked ? .gray
                                             : (supp.evidence == "strong" ? .white : .gray))
                            .strikethrough(checked, color: .secondary)
                        Spacer()
                        if let dose = supp.dose {
                            Text(dose)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.cyan)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(LivePressStyle())
        .sensoryFeedback(.selection, trigger: checked)
    }
}
