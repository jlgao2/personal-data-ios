import SwiftUI

/// The "did something else" sheet. Reused by every surface; only the
/// presets differ. Submit calls `DeviationStore.record` + posts to
/// `/v1/deviations` via TransportClient + refreshes streak + achievements.
///
/// Invariants:
///   * `.large` detent (three pickers + free text + toggle).
///   * Direction chips wrap to 2 rows on iPhone mini.
///   * Submit is disabled until a direction is picked.
struct DeviationSheet: View {

    let surface:        DeviationEntry.Surface
    let surfaceID:      String?
    /// Free-text snapshot of what the engine prescribed at log time.
    let prescribed:     String
    /// Default direction the caller wants pre-selected.
    let defaultDirection: DeviationEntry.Direction
    /// Optional callback fired after a successful local record + (best-effort) post.
    var onSubmit:       (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var direction:    DeviationEntry.Direction
    @State private var cause:        DeviationEntry.Cause? = nil
    @State private var actual:       String = ""
    @State private var actualQuant:  String = ""
    @State private var lockIn:       Bool   = false
    @State private var note:         String = ""
    @State private var posting:      Bool   = false

    init(surface: DeviationEntry.Surface,
         surfaceID: String?,
         prescribed: String,
         defaultDirection: DeviationEntry.Direction,
         defaultActual: String = "",
         defaultActualQuant: String = "",
         onSubmit: (() -> Void)? = nil) {
        self.surface          = surface
        self.surfaceID        = surfaceID
        self.prescribed       = prescribed
        self.defaultDirection = defaultDirection
        self.onSubmit         = onSubmit
        _direction    = State(initialValue: defaultDirection)
        _actual       = State(initialValue: defaultActual)
        _actualQuant  = State(initialValue: defaultActualQuant)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    directionSection
                    whatInsteadSection
                    causeSection
                    quantSection
                    noteSection
                    lockInSection
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Did something else")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(posting ? "Saving…" : "Save") { Task { await submit() } }
                        .disabled(posting)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(surfaceLabel.uppercased())
                .font(.caption2.monospaced())
                .tracking(2)
                .foregroundStyle(.cyan)
            if !prescribed.isEmpty {
                Text("Prescribed: \(prescribed)")
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Direction")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            DeviationFlowLayout(spacing: 8) {
                ForEach(DeviationEntry.Direction.allCases, id: \.self) { d in
                    chip(label: directionLabel(d), selected: direction == d) {
                        direction = d
                    }
                }
            }
        }
    }

    private var whatInsteadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What instead?")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            // Today's HK/Garmin sports go first so the activity the user
            // actually did is the easiest tap. Then the 90-day rolling top-N,
            // then the hardcoded fallback if neither is populated yet.
            let todays     = DeviationStore.todayWorkouts().map(\.sport)
            let alternates = DeviationStore.topAlternates(limit: 4)
            let fallback   = ["Cycling", "Run", "Yoga", "Swim", "Other strength", "Mobility"]
            let body       = alternates.count >= 4 ? alternates : fallback
            var seen = Set<String>()
            let pool = (todays + body).filter { seen.insert($0).inserted }
            DeviationFlowLayout(spacing: 8) {
                ForEach(pool, id: \.self) { name in
                    chip(label: name, selected: actual == name) { actual = name }
                }
            }
            TextField("Custom…", text: $actual)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.white)
        }
    }

    private var causeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why?")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            DeviationFlowLayout(spacing: 8) {
                ForEach(DeviationEntry.Cause.allCases, id: \.self) { c in
                    chip(label: causeLabel(c), selected: cause == c) {
                        cause = (cause == c) ? nil : c
                    }
                }
            }
        }
    }

    private var quantSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let placeholder = quantPlaceholder {
                Text(placeholder.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                TextField(placeholder.hint, text: $actualQuant)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note (optional)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            TextField("e.g. weather was perfect", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var lockInSection: some View {
        Toggle(isOn: $lockIn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This works — try it again")
                    .font(.body)
                Text("Marks the swap pattern for the adaptive note (won't auto-rewrite the plan).")
                    .font(.caption2.italic())
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.cyan)
    }

    // MARK: - Submit

    private func submit() async {
        posting = true
        defer { posting = false }

        let now = Date()
        let entry = DeviationEntry(
            ts:           now,
            surface:      surface,
            surfaceID:    surfaceID,
            direction:    direction,
            cause:        cause,
            prescribed:   prescribed,
            actual:       actual.trimmingCharacters(in: .whitespaces),
            actualQuant:  Double(actualQuant.trimmingCharacters(in: .whitespaces)),
            lockIn:       lockIn,
            note:         note.isEmpty ? nil : note
        )

        DeviationStore.record(entry, date: now)

        let cid = DeviationStore.clientID(surface: surface,
                                          surfaceID: surfaceID,
                                          date: now)
        let upload = DeviationUpload(
            client_id:   cid,
            ts:          ISO8601DateFormatter().string(from: now),
            surface:     entry.surface.rawValue,
            surface_id:  entry.surfaceID,
            direction:   entry.direction.rawValue,
            cause:       entry.cause?.rawValue,
            prescribed:  entry.prescribed,
            actual:      entry.actual,
            actual_quant: entry.actualQuant,
            lock_in:     entry.lockIn,
            note:        entry.note
        )
        _ = try? await iCloudTransport.shared.uploadDeviations([upload])

        // The deviation counts as completion for the slot — refresh
        // streak + achievements on the way out.
        if surface == .workout {
            DailyLock.setWorkoutDone(source: direction == .didSkip ? .skip : .manual,
                                     reason: cause?.rawValue,
                                     date: now)
        }
        _ = StreakState.refresh()
        _ = Achievements.refresh()

        onSubmit?()
        dismiss()
    }

    // MARK: - Tokens / labels

    private var surfaceLabel: String {
        switch surface {
        case .workout:        return "Workout"
        case .suppsAM:        return "Supps · morning"
        case .suppsPM:        return "Supps · evening"
        case .mindfulEating:  return "Mindful eating"
        case .actionCard:     return "Action card"
        case .adaptedSwap:    return "Adapted swap"
        }
    }

    private func directionLabel(_ d: DeviationEntry.Direction) -> String {
        switch d {
        case .didLess:        return "Did less"
        case .didMore:        return "Did more"
        case .didDifferent:   return "Did different"
        case .didSkip:        return "Skipped"
        case .didOutsidePlan: return "Off-plan"
        }
    }

    private func causeLabel(_ c: DeviationEntry.Cause) -> String {
        switch c {
        case .feltFresh:     return "Felt fresh"
        case .feltTired:     return "Felt tired"
        case .pain:          return "Pain"
        case .weather:       return "Weather"
        case .schedule:      return "Schedule"
        case .traveling:     return "Traveling"
        case .sick:          return "Sick"
        case .bored:         return "Bored"
        case .intuition:     return "Intuition"
        case .scheduledRest: return "Scheduled rest"
        case .noReason:      return "No reason"
        }
    }

    private struct QuantPlaceholder { let label: String; let hint: String }

    private var quantPlaceholder: QuantPlaceholder? {
        switch surface {
        case .workout:                return .init(label: "Duration (minutes)", hint: "e.g. 38")
        case .suppsAM, .suppsPM:      return .init(label: "Dose (mg)",          hint: "e.g. 200")
        case .mindfulEating, .actionCard, .adaptedSwap: return nil
        }
    }

    // MARK: - Chip

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(selected ? Color.black : Color.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Color.cyan : Color.cyan.opacity(0.13),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

/// Reuse the same FlowLayout strategy as SkipReasonSheet — duplicate locally
/// (renamed to avoid collision) to keep DeviationSheet self-contained.
private struct DeviationFlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, rowH: CGFloat = 0, totalH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth {
                totalH += rowH + spacing; x = 0; rowH = 0
            }
            rowH = max(rowH, s.height); x += s.width + spacing
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: totalH + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.minX + maxWidth {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            rowH = max(rowH, s.height); x += s.width + spacing
        }
    }
}
