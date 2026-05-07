import SwiftUI
import Charts

struct VitalsView: View {
    let vitals: [String: VitalSeries]
    let live: [String: Double]

    private static let labels: [String: (label: String, unit: String, decimals: Int)] = [
        "heart_rate_resting": ("Resting HR",   "bpm",         0),
        "vo2max":             ("VO₂ Max",      "mL/min·kg",   1),
        "weight":             ("Weight",       "lb",          1),
        "bp_systolic":        ("BP Systolic",  "mmHg",        0),
        "bp_diastolic":       ("BP Diastolic", "mmHg",        0),
        "sleep_minutes":      ("Sleep",        "min",         0),
        "exercise_minutes":   ("Exercise",     "min",         0),
    ]

    private static let displayOrder = [
        "heart_rate_resting", "sleep_minutes", "vo2max", "weight",
        "bp_systolic", "bp_diastolic", "exercise_minutes",
    ]

    private var orderedKeys: [String] {
        VitalsView.displayOrder.filter { vitals[$0] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("VITALS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                Text("90d window")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 1) {
                ForEach(orderedKeys, id: \.self) { key in
                    VitalRow(
                        key: key,
                        meta: VitalsView.labels[key],
                        series: vitals[key],
                        liveValue: live[key]
                    )
                }
            }
            .background(Color.white.opacity(0.05))
        }
    }
}

private struct VitalRow: View {
    let key: String
    let meta: (label: String, unit: String, decimals: Int)?
    let series: VitalSeries?
    let liveValue: Double?

    private var displayValue: Double? { liveValue ?? series?.latest }

    private var formattedValue: String {
        guard let v = displayValue, let m = meta else { return "—" }
        return String(format: "%.\(m.decimals)f", v)
    }

    private var trendArrow: String {
        switch series?.trend {
        case "up":   return "↑"
        case "down": return "↓"
        case "flat": return "→"
        default:     return ""
        }
    }

    private var trendColor: Color {
        // up = green for sleep/vo2max/exercise; red for RHR/weight/BP
        let goodWhenUp: Set<String> = ["vo2max", "sleep_minutes", "exercise_minutes"]
        switch series?.trend {
        case "up":   return goodWhenUp.contains(key) ? .green : .red
        case "down": return goodWhenUp.contains(key) ? .red : .green
        case "flat": return .secondary
        default:     return .secondary
        }
    }

    private var sparkData: [SparkPoint] {
        guard let pts = series?.series else { return [] }
        return pts.suffix(90).enumerated().map { i, p in SparkPoint(index: i, value: p.value) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text((meta?.label ?? key).uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedValue)
                        .font(.system(.title2, design: .serif).italic().weight(.medium))
                        .foregroundStyle(.white)
                    Text(meta?.unit ?? "")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if liveValue != nil {
                        Text("LIVE")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.green)
                            .tracking(1.5)
                    }
                }
                Text("\(trendArrow) \(series?.trend ?? "—") · last 30d")
                    .font(.caption2.monospaced())
                    .foregroundStyle(trendColor)
            }
            .frame(maxWidth: 130, alignment: .leading)

            // Sparkline
            if !sparkData.isEmpty {
                Chart(sparkData) { p in
                    LineMark(x: .value("i", p.index), y: .value("v", p.value))
                        .foregroundStyle(Color.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }
}

private struct SparkPoint: Identifiable {
    let index: Int
    let value: Double
    var id: Int { index }
}
