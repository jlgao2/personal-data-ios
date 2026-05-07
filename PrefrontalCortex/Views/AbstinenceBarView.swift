import SwiftUI

/// All-day abstinence tracker. Compact pill bar that wraps. Per-day
/// localStorage state (UserDefaults key 'tl_abstinences_<yyyy-mm-dd>').
struct AbstinenceBarView: View {
    let abstinences: [HealthProfile.Abstinence]

    @State private var done: [String: Bool] = readState()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALL-DAY · NON-CONSUMPTION")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            FlowLayout(spacing: 6) {
                ForEach(abstinences) { a in
                    let id = a.key ?? a.label
                    let isDone = done[id] ?? false
                    Button(action: {
                        done[id] = !isDone
                        write(state: done)
                    }) {
                        HStack(spacing: 6) {
                            Text(isDone ? "✓" : "·")
                                .font(.caption.monospaced())
                                .foregroundStyle(isDone ? Color.green : Color.cyan)
                            Text(a.label.uppercased())
                                .font(.caption2.monospaced())
                                .tracking(1.5)
                                .foregroundStyle(isDone ? Color.green : Color.gray)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(isDone ? Color.green : Color.white.opacity(0.15),
                                        lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static func todayKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private static func readState() -> [String: Bool] {
        let k = "tl_abstinences_\(todayKey())"
        guard let data = UserDefaults.standard.data(forKey: k),
              let m = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return m
    }
    private func write(state: [String: Bool]) {
        let k = "tl_abstinences_\(Self.todayKey())"
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: k)
        }
    }
}

/// Tiny FlowLayout for SwiftUI iOS 16+ — wraps children horizontally.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: sz.width, height: sz.height))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
