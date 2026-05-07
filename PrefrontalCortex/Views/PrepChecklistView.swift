import SwiftUI

struct PrepChecklistView: View {
    let items: [String]

    @AppStorage("prep_state") private var state: String = "{}"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRE-FLIGHT CHECK")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            VStack(spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, label in
                    PrepRow(idx: idx, label: label, current: todayState(), commit: setToday)
                }
            }
            .background(Color.white.opacity(0.05))
        }
    }

    private var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func todayState() -> [Bool] {
        guard let data = state.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: [Bool]].self, from: data),
              let arr = map[dayKey] else {
            return Array(repeating: false, count: items.count)
        }
        var arr2 = arr
        while arr2.count < items.count { arr2.append(false) }
        return Array(arr2.prefix(items.count))
    }

    private func setToday(_ arr: [Bool]) {
        var map: [String: [Bool]] = [:]
        if let data = state.data(using: .utf8),
           let existing = try? JSONDecoder().decode([String: [Bool]].self, from: data) {
            map = existing
        }
        map[dayKey] = arr
        if let data = try? JSONEncoder().encode(map),
           let s = String(data: data, encoding: .utf8) {
            state = s
        }
    }
}

private struct PrepRow: View {
    let idx: Int
    let label: String
    let current: [Bool]
    let commit: ([Bool]) -> Void

    private var done: Bool { current[idx] }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .foregroundStyle(done ? Color.green : Color.cyan)
            Text(label)
                .font(.body.italic())
                .foregroundStyle(done ? Color.secondary : Color.white)
                .strikethrough(done, color: .green)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
        .contentShape(Rectangle())
        .onTapGesture {
            var arr = current
            arr[idx].toggle()
            commit(arr)
        }
    }
}
