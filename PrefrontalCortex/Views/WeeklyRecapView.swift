import SwiftUI

/// Last 7d vs prior 7d across sleep / RHR / workouts / TL.
struct WeeklyRecapView: View {
    let vitals: [String: VitalSeries]
    let workouts: [Workout]

    fileprivate struct Cell: Identifiable {
        let name: String
        let unit: String
        let curr: Double?
        let prev: Double?
        let betterWhenHigher: Bool
        var id: String { name }
    }

    private static let day: TimeInterval = 86_400

    private func valueIn(series: [SeriesPoint], start: Date, end: Date) -> Double? {
        let f = ISO8601DateFormatter()
        let xs = series.compactMap { p -> Double? in
            // Accept dates as YYYY-MM-DD or full ISO; force midnight if date-only.
            let raw = p.date.count == 10 ? p.date + "T12:00:00+00:00" : p.date
            guard let d = f.date(from: raw) else { return nil }
            return d >= start && d < end ? p.value : nil
        }
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    private func computeCells() -> [Cell] {
        let now = Date()
        let lastStart = now.addingTimeInterval(-7 * Self.day)
        let prevStart = now.addingTimeInterval(-14 * Self.day)
        let prevEnd   = lastStart

        var cells: [Cell] = []

        if let s = vitals["sleep_minutes"]?.series {
            cells.append(Cell(
                name: "Sleep avg", unit: "min",
                curr: valueIn(series: s, start: lastStart, end: now),
                prev: valueIn(series: s, start: prevStart, end: prevEnd),
                betterWhenHigher: true
            ))
        }
        if let s = vitals["heart_rate_resting"]?.series {
            cells.append(Cell(
                name: "Resting HR", unit: "bpm",
                curr: valueIn(series: s, start: lastStart, end: now),
                prev: valueIn(series: s, start: prevStart, end: prevEnd),
                betterWhenHigher: false
            ))
        }

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let inWin = { (ts: String, s: Date, e: Date) -> Bool in
            let d = f.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
            guard let d else { return false }
            return d >= s && d < e
        }
        let woutLast = workouts.filter { inWin($0.ts_start, lastStart, now) }.count
        let woutPrev = workouts.filter { inWin($0.ts_start, prevStart, prevEnd) }.count
        cells.append(Cell(name: "Workouts", unit: "",
                          curr: Double(woutLast), prev: Double(woutPrev),
                          betterWhenHigher: true))
        let tlLast = workouts.filter { inWin($0.ts_start, lastStart, now) }
            .reduce(0.0) { $0 + ($1.training_load ?? 0) }
        let tlPrev = workouts.filter { inWin($0.ts_start, prevStart, prevEnd) }
            .reduce(0.0) { $0 + ($1.training_load ?? 0) }
        cells.append(Cell(name: "Training load", unit: "",
                          curr: tlLast, prev: tlPrev,
                          betterWhenHigher: true))
        return cells
    }

    var body: some View {
        let cells = computeCells()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("WEEKLY RECAP")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                Text("last 7d vs prior 7d")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                ForEach(cells) { c in RecapCell(cell: c) }
            }
            .background(Color.white.opacity(0.05))
        }
    }
}

private struct RecapCell: View {
    let cell: WeeklyRecapView.Cell

    private var trend: String {
        guard let a = cell.curr, let b = cell.prev, b != 0 else { return "—" }
        let diff = a - b
        let pct = abs(diff / b) * 100
        if pct < 3 { return "same" }
        let isBetter = (cell.betterWhenHigher && diff > 0) || (!cell.betterWhenHigher && diff < 0)
        return isBetter ? "better" : "worse"
    }

    private var trendColor: Color {
        switch trend {
        case "better": return .green
        case "worse":  return .red
        default:       return .secondary
        }
    }

    private var deltaText: String {
        guard let a = cell.curr, let b = cell.prev else { return "—" }
        let diff = a - b
        let sign = diff > 0 ? "+" : ""
        let dec = cell.name == "Workouts" ? 0 : 1
        return "\(sign)\(String(format: "%.\(dec)f", diff)) vs prior"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cell.name.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(cell.curr.map { String(format: "%.\(cell.name == "Workouts" ? 0 : 1)f", $0) } ?? "—")
                    .font(.system(.title2, design: .serif).italic().weight(.medium))
                    .foregroundStyle(.white)
                Text(cell.unit)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(deltaText)
                .font(.caption2.monospaced())
                .foregroundStyle(trendColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }
}
