import SwiftUI

/// Day-of-week heatmap — sleep / RHR / training-load / workouts by weekday.
/// Mirrors the web dashboard's DOW grid. Cell shading is per-column,
/// normalized between that column's min and max across the 7 days.
struct DOWHeatmapView: View {
    let stats: [DOWStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WEEKDAY PATTERNS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                Text("\(stats.first?.n ?? 0) days/cell median")
                    .font(.caption2.italic())
                    .foregroundStyle(.secondary)
            }

            if stats.isEmpty {
                Text("No weekday breakdown yet.")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        let sleeps = stats.compactMap { $0.sleep }
        let rhrs   = stats.compactMap { $0.rhr }
        let tls    = stats.compactMap { $0.tl }
        let minS = sleeps.min() ?? 0, maxS = sleeps.max() ?? 1
        let minR = rhrs.min() ?? 0,   maxR = rhrs.max() ?? 1
        let maxT = tls.max() ?? 1

        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                cell("DAY",    width: 40, isHeader: true)
                cell("SLEEP",  isHeader: true)
                cell("RHR",    isHeader: true)
                cell("TL",     isHeader: true)
                cell("WK#",    isHeader: true)
            }
            ForEach(stats) { s in
                HStack(spacing: 2) {
                    cell(s.dow, width: 40, isHeader: false, mono: true)
                    valueCell(value: s.sleep,  fmt: "%.0f",
                              shade: shade(s.sleep, minS, maxS),
                              tint: .green, alpha: 0.40)
                    valueCell(value: s.rhr,    fmt: "%.1f",
                              shade: shade(s.rhr, minR, maxR),
                              tint: .red, alpha: 0.35)
                    valueCell(value: s.tl,     fmt: "%.1f",
                              shade: shade(s.tl, 0, maxT),
                              tint: .cyan, alpha: 0.35)
                    cell("\(s.workouts)")
                }
            }
        }
    }

    private func shade(_ v: Double?, _ vmin: Double, _ vmax: Double) -> Double {
        guard let v, vmax > vmin else { return 0 }
        return min(1, max(0, (v - vmin) / (vmax - vmin)))
    }

    private func cell(_ text: String, width: CGFloat? = nil,
                      isHeader: Bool = false, mono: Bool = false) -> some View {
        Text(text)
            .font(isHeader || mono ? .caption2.monospaced() : .caption2)
            .foregroundStyle(isHeader ? .cyan : .white)
            .tracking(isHeader ? 1 : 0)
            .frame(maxWidth: width.map { _ in nil } ?? .infinity)
            .frame(width: width, height: 24)
            .background(isHeader ? Color.clear : Color.white.opacity(0.04))
    }

    private func valueCell(value: Double?, fmt: String,
                           shade: Double, tint: Color, alpha: Double) -> some View {
        Text(value.map { String(format: fmt, $0) } ?? "—")
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(tint.opacity(shade * alpha))
    }
}
