import SwiftUI

/// Renders the laptop adaptive engine's output: traffic-light pill,
/// intensity %, and the list of swaps / removed / added / notes.
struct AdaptedSessionView: View {
    let adapted: AdaptedSession
    let prescribedSession: DayProtocol?
    var onStart: (() -> Void)? = nil

    @State private var showDeviationSheet: Bool = false
    @State private var deviationDirection: DeviationEntry.Direction = .didDifferent
    @State private var deviationDefaultActual: String = ""
    @State private var deviationDefaultActualQuant: String = ""

    /// HK/Garmin workout(s) that landed today, pulled from `DeviationStore`.
    /// Drives the prominent "Log <Sport>" button below the Start pill — when
    /// the user has obviously done something other than the prescribed
    /// session, surface a one-tap log path pre-filled with that activity
    /// instead of making them hold-to-skip and type the sport.
    private var todaysSessions: [DeviationStore.TodayWorkout] {
        DeviationStore.todayWorkouts()
    }
    private var prescribedIsRest: Bool {
        (prescribedSession?.intensity_class ?? "").lowercased() == "rest"
    }

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
                if DailyLock.isWorkoutDone() {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("DONE")
                    }
                    .font(.caption2.monospaced().bold())
                    .tracking(1.5)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.6), lineWidth: 1))
                    .clipShape(Capsule())
                } else if let onStart {
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

            // If the user did an HK-logged workout today, surface a
            // prominent one-tap "Log <Sport>" button that opens the
            // DeviationSheet pre-filled with the actual activity + its
            // duration. Otherwise fall back to the small "hold to skip"
            // link (long-press → skip, tap → did-different).
            if !todaysSessions.isEmpty {
                logActualButton
                    .padding(.top, 4)
            } else {
                SkipWorkoutButton(onCommit: {
                    deviationDefaultActual = ""
                    deviationDefaultActualQuant = ""
                    deviationDirection = .didSkip
                    showDeviationSheet = true
                })
                .padding(.top, -2)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        deviationDefaultActual = ""
                        deviationDefaultActualQuant = ""
                        deviationDirection = .didDifferent
                        showDeviationSheet = true
                    }
                )
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
        .sheet(isPresented: $showDeviationSheet) {
            DeviationSheet(
                surface:    .workout,
                surfaceID:  nil,
                prescribed: prescribedSession?.session ?? (adapted.prescribed ?? ""),
                defaultDirection:   deviationDirection,
                defaultActual:      deviationDefaultActual,
                defaultActualQuant: deviationDefaultActualQuant
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - "Log <Sport>" pill (shown when today's HK has data)

    @ViewBuilder
    private var logActualButton: some View {
        let primary = todaysSessions.first
        let label   = primary.map { "LOG \($0.sport.uppercased()) (\($0.durationMin) MIN) ↩" }
                      ?? "LOG WHAT YOU DID ↩"
        Button {
            if let p = primary {
                deviationDefaultActual      = p.sport
                deviationDefaultActualQuant = String(p.durationMin)
            }
            // If the prescription is a rest day, treat the actual workout
            // as "outside plan"; otherwise it's "did different".
            deviationDirection = prescribedIsRest ? .didOutsidePlan : .didDifferent
            showDeviationSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(label)
            }
            .font(.caption2.monospaced().bold())
            .tracking(1.5)
            .foregroundStyle(.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.6), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(LivePressStyle())
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
