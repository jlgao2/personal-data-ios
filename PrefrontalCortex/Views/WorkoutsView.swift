import SwiftUI

struct WorkoutsView: View {
    let workouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("WORKOUTS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                Text("\(workouts.count) recent")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 1) {
                ForEach(workouts.prefix(15)) { w in
                    WorkoutRow(workout: w)
                }
                if workouts.count > 15 {
                    Text("+ \(workouts.count - 15) earlier sessions")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(Color.black.opacity(0.4))
                }
            }
            .background(Color.white.opacity(0.05))
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    private var dateString: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: workout.ts_start) ?? ISO8601DateFormatter().date(from: workout.ts_start) else {
            return String(workout.ts_start.prefix(10))
        }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: d)
    }

    private var durationString: String {
        guard let s = workout.duration_s else { return "" }
        let h = Int(s / 3600)
        let m = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(dateString)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        Spacer()
                    }
                    Text(workout.label)
                        .font(.body.italic())
                        .foregroundStyle(.white)
                    if let sport = workout.sport {
                        Text(sport)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.cyan)
                            .tracking(1.5)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(durationString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                    if let hr = workout.avg_hr {
                        Text("\(Int(hr)) bpm avg")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let tl = workout.training_load {
                        Text("TL \(Int(tl))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(tl > 80 ? .red : tl > 40 ? .cyan : .secondary)
                    }
                }
            }
            if let zones = workout.hr_zones {
                HRZoneBar(zones: zones)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
    }
}

private struct HRZoneBar: View {
    let zones: [String: Int]

    private var total: Double {
        zones.values.reduce(0) { $0 + Double($1) }
    }

    private static let colors: [Color] = [
        Color.gray.opacity(0.5), .green, Color.cyan.opacity(0.7),
        .cyan, .yellow, .red,
    ]

    var body: some View {
        // Previously each segment was sized as `pct * 280` (hardcoded
        // width). Sum of all six segments could reach ~280pt; combined
        // with WorkoutRow's horizontal padding (24pt) and the planTab's
        // outer padding (32pt), the row's intrinsic width crept into
        // 336pt territory — which overflows the safe-area width on
        // iPhone SE / 13 mini (375pt) and with display zoom on. That
        // overflow propagated all the way up through the planTab
        // ScrollView, manifesting as a sideways scroll on the entire
        // tab. Switch to a GeometryReader-sized bar so the segments
        // share the parent's actual width.
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { z in
                    let v = Double(zones["zone_\(z)"] ?? 0)
                    let pct = total > 0 ? v / total : 0
                    if pct > 0 {
                        Rectangle()
                            .fill(WorkoutsView_HRZoneBar_color(z))
                            .frame(width: max(2, CGFloat(pct) * geo.size.width),
                                   height: 4)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 1))
        }
        .frame(height: 4)
    }
}

private func WorkoutsView_HRZoneBar_color(_ z: Int) -> Color {
    switch z {
    case 0: return Color.gray.opacity(0.5)
    case 1: return .green
    case 2: return Color.cyan.opacity(0.7)
    case 3: return .cyan
    case 4: return .yellow
    case 5: return .red
    default: return .gray
    }
}
