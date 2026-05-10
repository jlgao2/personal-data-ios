import SwiftUI

/// Renders the laptop adaptive engine's output: traffic-light pill,
/// intensity %, and the list of swaps / removed / added / notes.
struct AdaptedSessionView: View {
    let adapted: AdaptedSession
    let prescribedSession: DayProtocol?
    var onStart: (() -> Void)? = nil

    @State private var showDeviationSheet: Bool = false

    private var lightColor: Color {
        switch adapted.traffic_light {
        case "green": return .green
        case "amber": return .cyan
        case "red":   return .red
        default:      return .secondary
        }
    }

    private var intensityPct: Int {
        Int(((adapted.intensity_modifier ?? 1.0) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY · SESSION")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                if let day = adapted.program_day {
                    Text(day.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                }
                if let onStart {
                    Button(action: onStart) {
                        HStack(spacing: 4) {
                            Text("START")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption2.monospaced().bold())
                        .tracking(1.5)
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(LivePressStyle())
                }
            }

            if let entry = DeviationStore.entry(for: .workout) {
                DeviationChip(entry: entry)
            }

            // The skip link still long-presses to commit, but now opens
            // the unified DeviationSheet — skip is one branch alongside
            // "did less / did more / did different / off-plan".
            SkipWorkoutButton()
                .padding(.top, -2)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        showDeviationSheet = true
                    }
                )
                .sheet(isPresented: $showDeviationSheet) {
                    DeviationSheet(
                        surface:    .workout,
                        surfaceID:  nil,
                        prescribed: prescribedSession?.session ?? (adapted.prescribed ?? ""),
                        defaultDirection: .didDifferent
                    )
                    .presentationDetents([.large])
                }

            // Traffic light header card
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text((adapted.traffic_light ?? "—").uppercased())
                        .font(.caption.monospaced().weight(.bold))
                        .tracking(3)
                        .foregroundStyle(lightColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(lightColor, lineWidth: 1))
                    Text("\(intensityPct)% intensity")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if let reason = adapted.intensity_reason {
                    Text(reason)
                        .font(.footnote.italic())
                        .foregroundStyle(.secondary)
                }
                if let prescribed = adapted.prescribed {
                    Text(prescribed)
                        .font(.body.italic())
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.4))
            .overlay(alignment: .leading) {
                Rectangle().fill(lightColor).frame(width: 2)
            }

            // Per-rule output rows
            ForEach(adapted.swaps ?? []) { s in
                AdjRow(severity: .warn, prefix: "↻", line1: AnyView(
                    HStack(spacing: 4) {
                        Text(s.original).strikethrough(color: .secondary)
                        Text("→").foregroundStyle(.secondary)
                        Text(s.replacement).bold()
                    }
                    .font(.body.italic())
                ), reason: s.reason)
            }
            ForEach(adapted.removed ?? []) { r in
                AdjRow(severity: .warn, prefix: "✗", line1: AnyView(
                    Text(r.item).strikethrough().foregroundStyle(.secondary).font(.body.italic())
                ), reason: r.reason)
            }
            ForEach(adapted.added ?? []) { a in
                AdjRow(severity: .info, prefix: "+", line1: AnyView(
                    Text(a.item).bold().font(.body.italic())
                ), reason: a.reason)
            }
            ForEach((adapted.notes ?? []).indices, id: \.self) { i in
                let n = (adapted.notes ?? [])[i]
                AdjRow(severity: .info, prefix: "·", line1: AnyView(
                    Text(n).font(.body.italic())
                ), reason: nil)
            }

            // Static prescribed list (rehab/warmup/main/core), shown after the
            // adjustments so the user can see the underlying program.
            if let p = prescribedSession {
                VStack(alignment: .leading, spacing: 8) {
                    SessionBlock(title: "Rehab",  items: p.rehab ?? [])
                    SessionBlock(title: "Warmup", items: p.warmup ?? [])
                    SessionBlock(title: "Main",   items: p.main ?? [])
                    SessionBlock(title: "Core",   items: p.core ?? [])
                }
                .padding(.top, 4)
            }
        }
    }
}

private enum AdjSeverity { case info, warn }

private struct AdjRow: View {
    let severity: AdjSeverity
    let prefix: String
    let line1: AnyView
    let reason: String?

    private var color: Color {
        switch severity {
        case .warn: return .cyan
        case .info: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(prefix).foregroundStyle(color).font(.caption.monospaced())
                line1
            }
            if let r = reason {
                Text(r).font(.footnote.italic()).foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
    }
}

private struct SessionBlock: View {
    let title: String
    let items: [String]
    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.footnote.italic())
                        .foregroundStyle(.white)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.3))
        }
    }
}
