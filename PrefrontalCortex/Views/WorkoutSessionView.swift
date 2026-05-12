import SwiftUI
import WidgetKit

/// Full-screen workout tracker — presented via .fullScreenCover from
/// AdaptedSessionView's "Start →" button. Parses the prescribed exercises
/// (rehab/warmup/main/core), shows them as cards, and lets you log each
/// set with big-finger ± paddles. The active set is the focus; pending
/// and completed sets collapse to thin summary rows.
///
/// State:
///   - per-day per-exercise per-set values live in UserDefaults
///     (key: workout_<date>) so swiping between exercises doesn't lose
///     progress and reopening continues where you left off
///   - last working weight per exercise persists across days
///     (key: weight_<exercise>) so set 1 starts where you left off
struct WorkoutSessionView: View {
    let dayKey: String
    let prescribed: DayProtocol?
    let trafficLight: String?
    let intensityPct: Int

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @AppStorage("workout_unit") private var unitRaw: String = WorkoutUnit.pounds.rawValue

    private var unit: WorkoutUnit { WorkoutUnit(rawValue: unitRaw) ?? .pounds }

    /// exerciseKey → array of SetEntry, one per prescribed set
    @State private var sets: [String: [SetEntry]] = [:]
    /// Currently focused (exercise, set index)
    @State private var focused: Focus? = nil
    /// Set currently being edited via the custom-weight alert (nil = closed).
    @State private var customWeightTarget: Focus? = nil
    @State private var customWeightInput: String = ""

    struct SetEntry: Codable, Equatable {
        var weight: Double
        var reps: Int
        var completed: Bool
        var bandColor: String? = nil   // present iff parsed.isBand
    }
    struct Focus: Equatable {
        let exerciseKey: String
        let setIndex: Int
    }

    private var lightColor: Color {
        switch trafficLight {
        case "green": return .green
        case "amber": return .cyan
        case "red":   return .red
        default:      return .secondary
        }
    }

    var body: some View {
        ZStack {
            AnimatedAuraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerCard
                    if let p = prescribed {
                        section("REHAB",  items: p.rehab  ?? [])
                        section("WARMUP", items: p.warmup ?? [])
                        section("MAIN",   items: p.main   ?? [])
                        section("CORE",   items: p.core   ?? [])
                    } else {
                        Text("No prescribed session for \(dayKey).")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    Color.clear.frame(height: 60)
                }
                .padding()
                .padding(.top, 56)
            }
            .overlay(alignment: .topLeading) {
                Button("Cancel") { dismiss() }
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 16).padding(.leading, 16)
                    .buttonStyle(LivePressStyle())
            }
            .overlay(alignment: .topTrailing) {
                Button("Done") { Task { await commitAndDismiss() } }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .padding(.top, 16).padding(.trailing, 16)
                    .buttonStyle(LivePressStyle())
            }
        }
        .safeAreaInset(edge: .top) {
            if #available(iOS 16.2, *) {
                LiveActivityDisabledBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadState() }
        .alert("Custom weight (\(unit.label))",
               isPresented: Binding(
                    get: { customWeightTarget != nil },
                    set: { if !$0 { customWeightTarget = nil } }
               )) {
            TextField("Weight", text: $customWeightInput)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { }
            Button("Log set") { commitCustomWeight() }
        } message: {
            Text("Type the exact weight to log this set with — useful for off-grid dumbbells or plate combos the presets don't reach.")
        }
    }

    private func commitCustomWeight() {
        guard let target = customWeightTarget else { return }
        let normalized = customWeightInput
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let weight = Double(normalized),
              let arr = sets[target.exerciseKey],
              target.setIndex < arr.count else { return }
        let entry = arr[target.setIndex]
        logSet(weight: max(0, weight), reps: entry.reps,
               key: target.exerciseKey, index: target.setIndex)
        customWeightTarget = nil
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayKey.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                if let tl = trafficLight {
                    Text(tl.uppercased())
                        .font(.caption2.monospaced().bold())
                        .tracking(2)
                        .foregroundStyle(lightColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(lightColor, lineWidth: 1))
                }
                Text("\(intensityPct)%")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let session = prescribed?.session {
                Text(session)
                    .font(.title3.italic())
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func section(_ title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                ForEach(items, id: \.self) { raw in
                    let parsed = parseExercise(raw)
                    let key = exerciseKey(raw)
                    exerciseCard(parsed: parsed, key: key)
                }
            }
        }
    }

    // MARK: - Exercise card

    /// Warm-up suggestion line — shown above the sets for any exercise
    /// with non-trivial weight. Gives a concrete answer to "what should I
    /// warm up with?" instead of leaving the user to guess.
    @ViewBuilder
    private func warmupHint(workingWeight: Double) -> some View {
        let warmups = warmupSuggestions(workingWeight: workingWeight, unit: unit)
        if !warmups.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "flame")
                    .font(.caption2)
                Text("warm up: " + warmups.map { "\(unit.formatStep($0)) \(unit.label) × 5" }
                                          .joined(separator: ", "))
                    .font(.caption2.italic())
            }
            .foregroundStyle(.orange.opacity(0.85))
        }
    }

    @ViewBuilder
    private func exerciseCard(parsed: ParsedExercise, key: String) -> some View {
        let entries = sets[key] ?? []
        let unitLabel = parsed.isTime ? "sec" : "reps"
        let doneCount = entries.filter { $0.completed }.count
        let targetText: String = {
            if parsed.isAMRAP { return "Target \(parsed.sets) × AMRAP" }
            return "Target \(parsed.sets) × \(parsed.reps) \(unitLabel)"
        }()

        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(parsed.name)
                    .font(.body.italic())
                    .foregroundStyle(.white)
                Spacer()
                Text("\(doneCount)/\(entries.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(doneCount == entries.count && !entries.isEmpty ? .cyan : .secondary)
            }
            Text(targetText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            // Warm-up hint only applies to free-weight / machine work.
            // Mobility holds and band work skip it.
            if !parsed.isTime && !parsed.isBand {
                warmupHint(workingWeight: entries.first?.weight ?? 0)
            }

            // Sets
            VStack(spacing: 6) {
                ForEach(entries.indices, id: \.self) { i in
                    let entry = entries[i]
                    let isFocused = focused == Focus(exerciseKey: key, setIndex: i)
                    if isFocused {
                        activeSetEditor(key: key, index: i, entry: entry, parsed: parsed)
                    } else {
                        summaryRow(index: i, entry: entry, parsed: parsed) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                focused = Focus(exerciseKey: key, setIndex: i)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.5))
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
    }

    // MARK: - Active set editor

    private func activeSetEditor(key: String, index: Int, entry: SetEntry, parsed: ParsedExercise) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("SET \(index + 1)")
                    .font(.caption2.monospaced().bold())
                    .tracking(2)
                    .foregroundStyle(.cyan)
                Spacer()
                Text("base \(setSummary(entry: entry, parsed: parsed))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation { focused = nil }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
                .buttonStyle(LivePressStyle())
            }

            if parsed.isTime {
                // Mobility / hold — only duration matters. No weight, no band.
                durationPresetCluster(key: key, index: index, entry: entry)
            } else if parsed.isBand {
                // Resistance band — pick a color, then commit reps.
                bandColorPicker(key: key, index: index, entry: entry)
                repClusterSection(key: key, index: index, entry: entry, parsed: parsed)
            } else {
                // Free weight / machine — both weight + reps in play.
                weightClusterSection(key: key, index: index, entry: entry)
                repClusterSection(key: key, index: index, entry: entry, parsed: parsed)
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.cyan.opacity(0.25)))
    }

    private func weightClusterSection(key: String, index: Int, entry: SetEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WEIGHT (\(unit.label.uppercased()))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            weightPresetButton(.bigUp,   key: key, index: index, entry: entry)
            weightPresetButton(.smallUp, key: key, index: index, entry: entry)
            weightPresetButton(.same,    key: key, index: index, entry: entry)
            weightPresetButton(.down,    key: key, index: index, entry: entry)
            customWeightButton(key: key, index: index, entry: entry)
        }
    }

    /// 5th row under the weight presets — opens a number-pad alert so the
    /// user can type any value (off-grid dumbbells, oddball plates, etc.).
    private func customWeightButton(key: String, index: Int, entry: SetEntry) -> some View {
        Button {
            customWeightInput = unit.formatStep(entry.weight)
            customWeightTarget = Focus(exerciseKey: key, setIndex: index)
        } label: {
            presetRow(label: "✎   custom…",
                      preview: "type any value",
                      color: .purple)
        }
        .buttonStyle(LivePressStyle())
    }

    private func repClusterSection(key: String, index: Int, entry: SetEntry, parsed: ParsedExercise) -> some View {
        let label = parsed.isTime ? "DURATION (SEC)" : "REPS"
        return VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            repPresetButton(.bigUp,   key: key, index: index, entry: entry, parsed: parsed)
            repPresetButton(.smallUp, key: key, index: index, entry: entry, parsed: parsed)
            repPresetButton(.same,    key: key, index: index, entry: entry, parsed: parsed)
            repPresetButton(.down,    key: key, index: index, entry: entry, parsed: parsed)
        }
    }

    private func durationPresetCluster(key: String, index: Int, entry: SetEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DURATION (SEC)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            // Bigger seconds-based deltas for time work
            durationPresetButton(.bigUp,   key: key, index: index, entry: entry)
            durationPresetButton(.smallUp, key: key, index: index, entry: entry)
            durationPresetButton(.same,    key: key, index: index, entry: entry)
            durationPresetButton(.down,    key: key, index: index, entry: entry)
        }
    }

    private func bandColorPicker(key: String, index: Int, entry: SetEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BAND COLOR")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            HStack(spacing: 10) {
                ForEach(BandColor.allCases, id: \.self) { c in
                    let selected = entry.bandColor == c.rawValue
                    Button {
                        logBandSet(color: c, key: key, index: index, entry: entry)
                    } label: {
                        Circle()
                            .fill(c.swiftUIColor)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().strokeBorder(
                                    selected ? Color.white : Color.white.opacity(0.15),
                                    lineWidth: selected ? 2 : 1
                                )
                            )
                            .shadow(color: selected ? c.swiftUIColor.opacity(0.5) : .clear,
                                    radius: 6, x: 0, y: 0)
                    }
                    .buttonStyle(LivePressStyle())
                    .sensoryFeedback(.selection, trigger: selected)
                }
            }
            Text("Tap a color to log this set with that band + current reps.")
                .font(.caption2.italic())
                .foregroundStyle(.secondary)
        }
    }

    private enum Preset { case bigUp, smallUp, same, down

        var color: Color {
            switch self {
            case .bigUp:   return .green
            case .smallUp: return .cyan
            case .same:    return .white
            case .down:    return .orange
            }
        }
        var arrow: String {
            switch self {
            case .bigUp:   return "↑↑"
            case .smallUp: return "↑"
            case .same:    return "="
            case .down:    return "↓"
            }
        }
    }

    private func weightDelta(_ p: Preset) -> Double {
        switch p {
        case .bigUp:   return  unit.largeStep
        case .smallUp: return  unit.smallStep
        case .same:    return  0
        case .down:    return -unit.smallStep
        }
    }

    private func repDelta(_ p: Preset) -> Int {
        switch p {
        case .bigUp:   return  2
        case .smallUp: return  1
        case .same:    return  0
        case .down:    return -1
        }
    }

    private func durationDelta(_ p: Preset) -> Int {
        switch p {
        case .bigUp:   return  15
        case .smallUp: return  5
        case .same:    return  0
        case .down:    return -5
        }
    }

    /// Per-mode summary: "60 sec" for time, "Green band × 12" for band,
    /// "135 lb × 10" for normal weighted work.
    private func setSummary(entry: SetEntry, parsed: ParsedExercise) -> String {
        if parsed.isTime {
            return "\(entry.reps) sec"
        }
        if parsed.isBand {
            let colorName = entry.bandColor.flatMap(BandColor.init(rawValue:))?.displayName ?? "—"
            return "\(colorName) band × \(entry.reps)"
        }
        return "\(formattedWeight(entry.weight)) × \(entry.reps)"
    }

    private func weightPresetButton(_ p: Preset, key: String, index: Int, entry: SetEntry) -> some View {
        let delta = weightDelta(p)
        let newWeight = max(0, entry.weight + delta)
        let preview = newWeight == 0
            ? "BW × \(entry.reps)"
            : "\(formattedWeight(newWeight)) × \(entry.reps)"
        let label = p == .same ? "=   same"
            : "\(p.arrow)   \(delta >= 0 ? "+" : "−")\(unit.formatStep(abs(delta)))"

        return Button {
            logSet(weight: newWeight, reps: entry.reps, key: key, index: index)
        } label: {
            presetRow(label: label, preview: preview, color: p.color)
        }
        .buttonStyle(LivePressStyle())
    }

    private func repPresetButton(_ p: Preset, key: String, index: Int,
                                 entry: SetEntry, parsed: ParsedExercise) -> some View {
        let delta = repDelta(p)
        let newReps = max(0, entry.reps + delta)
        let previewBase: String
        if parsed.isBand {
            let colorName = entry.bandColor.flatMap(BandColor.init(rawValue:))?.displayName ?? "Band"
            previewBase = "\(colorName) band"
        } else {
            previewBase = formattedWeight(entry.weight)
        }
        let preview = "\(previewBase) × \(newReps)"
        let label = p == .same ? "=   same"
            : "\(p.arrow)   \(delta >= 0 ? "+" : "−")\(abs(delta)) rep\(abs(delta) == 1 ? "" : "s")"

        return Button {
            logSetPreservingMode(reps: newReps, key: key, index: index, entry: entry, parsed: parsed)
        } label: {
            presetRow(label: label, preview: preview, color: p.color)
        }
        .buttonStyle(LivePressStyle())
    }

    private func durationPresetButton(_ p: Preset, key: String, index: Int, entry: SetEntry) -> some View {
        let delta = durationDelta(p)
        let newSec = max(0, entry.reps + delta)   // reps field doubles as seconds for isTime exercises
        let preview = "\(newSec) sec"
        let label = p == .same ? "=   same"
            : "\(p.arrow)   \(delta >= 0 ? "+" : "−")\(abs(delta)) sec"

        return Button {
            logSet(weight: 0, reps: newSec, key: key, index: index)
        } label: {
            presetRow(label: label, preview: preview, color: p.color)
        }
        .buttonStyle(LivePressStyle())
    }

    /// Commit a set while preserving its mode (band color stays for band sets,
    /// weight stays for weighted sets).
    private func logSetPreservingMode(reps: Int, key: String, index: Int,
                                      entry: SetEntry, parsed: ParsedExercise) {
        guard var arr = sets[key], index < arr.count else { return }
        arr[index].reps = max(0, reps)
        if !parsed.isBand {
            arr[index].weight = entry.weight
            arr[index].bandColor = nil
        }
        sets[key] = arr
        markComplete(key: key, index: index)
    }

    /// Log a band set: pick the color, default reps from current entry. Stores
    /// the color name; weight is 0 (unused for band work).
    private func logBandSet(color: BandColor, key: String, index: Int, entry: SetEntry) {
        guard var arr = sets[key], index < arr.count else { return }
        arr[index].bandColor = color.rawValue
        arr[index].weight = 0
        // reps stays as currently shown (default from prescription or last set)
        sets[key] = arr
        // Remember last band color for next session.
        UserDefaults.standard.set(color.rawValue, forKey: "band_\(key)")
        markComplete(key: key, index: index)
    }

    private func presetRow(label: String, preview: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.body.monospaced().weight(.semibold))
            Spacer()
            Text(preview)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .foregroundStyle(color)
        .background(color.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.35)))
    }

    private func paddleControl(label: String,
                               value: Double,
                               unit: String,
                               step: Double,
                               format: String,
                               onMinus: @escaping () -> Void,
                               onPlus:  @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            HStack(spacing: 18) {
                paddleButton(symbol: "minus", action: onMinus)
                VStack(spacing: 0) {
                    Text(String(format: format, value))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: value))
                    Text(unit)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 100)
                paddleButton(symbol: "plus", action: onPlus)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: value)
        }
    }

    private func paddleButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 56, height: 56)
                .background(Color.cyan.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(Color.cyan.opacity(0.35)))
        }
        .buttonStyle(LivePressStyle())
        .sensoryFeedback(.selection, trigger: UUID())  // soft tick on every press
    }

    // MARK: - Summary row (pending or completed)

    private func summaryRow(index: Int, entry: SetEntry, parsed: ParsedExercise,
                            onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.completed ? .cyan : .secondary)
                    .symbolEffect(.bounce.up, value: entry.completed)
                Text("Set \(index + 1)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(entry.completed ? 0.5 : 0.85))
                Spacer()
                if entry.completed {
                    Text(setSummary(entry: entry, parsed: parsed))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text("tap to log")
                        .font(.caption2.italic())
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(LivePressStyle())
    }

    // MARK: - Mutators

    private func adjustWeight(key: String, index: Int, by delta: Double) {
        guard var arr = sets[key], index < arr.count else { return }
        arr[index].weight = max(0, arr[index].weight + delta)
        sets[key] = arr
        saveState()
    }

    /// Set this set's weight + reps, then mark complete (inherits into next
    /// set + advances focus). Called by every preset-button tap.
    private func logSet(weight: Double, reps: Int, key: String, index: Int) {
        guard var arr = sets[key], index < arr.count else { return }
        arr[index].weight = max(0, weight)
        arr[index].reps   = max(0, reps)
        sets[key] = arr
        markComplete(key: key, index: index)
    }

    private func adjustReps(key: String, index: Int, by delta: Int) {
        guard var arr = sets[key], index < arr.count else { return }
        arr[index].reps = max(0, arr[index].reps + delta)
        sets[key] = arr
        saveState()
    }

    private func markComplete(key: String, index: Int) {
        guard var arr = sets[key], index < arr.count else { return }
        arr[index].completed = true
        sets[key] = arr
        // Inherit weight/reps into the next set (if it exists and isn't done)
        let next = index + 1
        if next < arr.count && !arr[next].completed {
            arr[next].weight = arr[index].weight
            arr[next].reps   = arr[index].reps
            sets[key] = arr
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                focused = Focus(exerciseKey: key, setIndex: next)
            }
        } else {
            withAnimation { focused = nil }
        }
        // Remember this exercise's working weight for next session.
        UserDefaults.standard.set(arr[index].weight, forKey: weightMemoryKey(for: key))
        saveState()
        syncToLockScreen()
    }

    /// Mirror current workout state into the App-Group store the lock-screen
    /// widget reads. Called on focus changes and after every set commit so
    /// the widget always shows the next-set prompt that matches the in-app
    /// active editor.
    private func syncToLockScreen() {
        guard let focused else {
            LockScreenWorkoutStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 16.2, *) {
                Task { await WorkoutLiveActivity.endAll(immediate: true) }
            }
            return
        }
        let entries = sets[focused.exerciseKey] ?? []
        let raw = allPrescribedItems().first { exerciseKey($0) == focused.exerciseKey } ?? ""
        let parsed = parseExercise(raw)

        let mode: LockScreenWorkoutState.Mode = {
            if parsed.isTime { return .time }
            if parsed.isBand { return .band }
            if parsed.isAMRAP { return .amrap }
            return .free
        }()

        let entry = entries[safe: focused.setIndex] ?? .init(weight: 0, reps: 0, completed: false)

        // Queue of upcoming exercises so the lock-screen intent can advance
        // past the current exercise's last set without falling off the end
        // of the workout.
        let allItems = allPrescribedItems()
        let currentIdx = allItems.firstIndex { exerciseKey($0) == focused.exerciseKey } ?? -1
        var queue: [LockScreenWorkoutState.QueuedExercise] = []
        if currentIdx >= 0 {
            for raw in allItems[(currentIdx + 1)...] {
                let qKey = exerciseKey(raw)
                let qParsed = parseExercise(raw)
                let qEntries = sets[qKey] ?? []
                guard let firstPending = qEntries.firstIndex(where: { !$0.completed }) else {
                    continue   // already complete — skip
                }
                let qEntry = qEntries[firstPending]
                let qMode: LockScreenWorkoutState.Mode = {
                    if qParsed.isTime { return .time }
                    if qParsed.isBand { return .band }
                    if qParsed.isAMRAP { return .amrap }
                    return .free
                }()
                queue.append(.init(
                    exerciseKey: qKey,
                    exerciseName: qParsed.name,
                    totalSets: qParsed.sets,
                    mode: qMode,
                    lastWeight: qEntry.weight,
                    lastReps: qEntry.reps,
                    bandColor: qEntry.bandColor
                ))
            }
        }

        let state = LockScreenWorkoutState(
            inProgress: true,
            exerciseKey: focused.exerciseKey,
            exerciseName: parsed.name,
            setIndex: focused.setIndex,
            totalSets: parsed.sets,
            lastWeight: entry.weight,
            lastReps: entry.reps,
            stage: .weight,
            stagedWeight: nil,
            mode: mode,
            bandColor: entry.bandColor,
            unit: unit.label,
            queue: queue
        )
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()

        // Live Activity: idempotent — start() refreshes if one already exists,
        // requests a new one otherwise. Title combines the day key with the
        // session label from the prescribed bundle when present.
        if #available(iOS 16.2, *) {
            let title = (prescribed?.session ?? dayKey)
            WorkoutLiveActivity.start(state: state, title: title)
            Task { await WorkoutLiveActivity.refresh() }
        }
    }

    private func formattedWeight(_ w: Double) -> String {
        if w == 0 { return "BW" }
        return "\(unit.formatStep(w)) \(unit.label)"
    }

    // MARK: - State persistence (per-day workout)

    private static func todayDateString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static var stateKey: String { "workout_\(todayDateString())" }

    private func weightMemoryKey(for exerciseKey: String) -> String {
        "weight_\(exerciseKey)"
    }

    private func allPrescribedItems() -> [String] {
        var out: [String] = []
        out.append(contentsOf: prescribed?.rehab ?? [])
        out.append(contentsOf: prescribed?.warmup ?? [])
        out.append(contentsOf: prescribed?.main ?? [])
        out.append(contentsOf: prescribed?.core ?? [])
        return out
    }

    private func loadState() {
        var fresh: [String: [SetEntry]] = [:]
        for raw in allPrescribedItems() {
            let parsed = parseExercise(raw)
            let key = exerciseKey(raw)

            // Mode-specific defaults:
            //   - band : color from memory (default green = medium); weight = 0
            //   - time : reps field carries seconds, weight = 0
            //   - free : weight from memory or sensible default (in user's unit)
            var weight: Double = 0
            var bandColor: String? = nil

            if parsed.isBand {
                bandColor = UserDefaults.standard.string(forKey: "band_\(key)") ?? BandColor.green.rawValue
            } else if parsed.isTime {
                weight = 0
            } else {
                if let stored = UserDefaults.standard.object(forKey: weightMemoryKey(for: key)) as? Double {
                    weight = stored
                } else {
                    weight = unit.displayValue(fromPounds: defaultWeight(for: parsed.name))
                }
            }

            fresh[key] = (0..<parsed.sets).map { _ in
                SetEntry(weight: weight, reps: parsed.reps, completed: false, bandColor: bandColor)
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.stateKey),
           let saved = try? JSONDecoder().decode([String: [SetEntry]].self, from: data) {
            for (k, v) in saved where fresh[k] != nil {
                if v.count == fresh[k]?.count { fresh[k] = v }
            }
        }
        sets = fresh

        for (k, arr) in sortedSetsKeys() {
            if let firstPending = arr.firstIndex(where: { !$0.completed }) {
                focused = Focus(exerciseKey: k, setIndex: firstPending)
                syncToLockScreen()
                return
            }
        }
        syncToLockScreen()
    }

    private func sortedSetsKeys() -> [(String, [SetEntry])] {
        var out: [(String, [SetEntry])] = []
        for raw in allPrescribedItems() {
            let key = exerciseKey(raw)
            if let entries = sets[key] {
                out.append((key, entries))
            }
        }
        return out
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    // MARK: - Commit (tap Done)

    private func commitAndDismiss() async {
        // Roll all completed sets into a single self-logged session row,
        // posted to /v1/sessions for the laptop spine to ingest.
        let total = sets.values.flatMap { $0 }.filter { $0.completed }
        let totalReps = total.reduce(0) { $0 + $1.reps }
        let avgWeight = total.isEmpty ? 0
            : total.map { $0.weight }.reduce(0, +) / Double(total.count)

        let dayLabel = (prescribed?.session ?? dayKey)
        let note = "\(total.count) sets logged · avg \(Int(avgWeight)) lb · \(totalReps) total reps"

        if total.isEmpty {
            store.lastUploadResult = "No sets logged"
            dismiss()
            return
        }

        let row = SessionUpload(
            client_id:    "\(Self.todayDateString())_\(dayKey)",
            ts:           ISO8601DateFormatter().string(from: Date()),
            sport:        "STRENGTH_TRAINING",
            duration_min: max(15, total.count * 3),
            rpe:          6,
            note:         "\(dayLabel) · \(note)"
        )
        do {
            _ = try await TransportClient.shared.uploadSessions([row])
            store.lastUploadResult = "Workout logged · \(total.count) sets"
        } catch {
            store.lastUploadResult = "Logged locally (laptop unreachable)"
        }
        DailyLock.setWorkoutDone(source: .manual)
        _ = StreakState.refresh()
        _ = Achievements.refresh()
        LockScreenWorkoutStore.clear()
        if #available(iOS 16.2, *) {
            await WorkoutLiveActivity.endAll(immediate: true)
        }
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

// MARK: - Exercise string parsing

struct ParsedExercise {
    let name: String
    let sets: Int
    let reps: Int
    let isTime: Bool
    let isAMRAP: Bool       // "as many reps as possible" — fluid target
    let isBand: Bool        // resistance-band exercise → color picker, no weight
}

/// Resistance-band tension by color (Theraband-ish convention,
/// light → heavy). Stored as the rawValue string in SetEntry.bandColor.
enum BandColor: String, CaseIterable, Codable {
    case yellow, red, green, blue, black

    var displayName: String { rawValue.capitalized }

    var swiftUIColor: Color {
        switch self {
        case .yellow: return .yellow
        case .red:    return .red
        case .green:  return .green
        case .blue:   return .blue
        case .black:  return Color(white: 0.35)  // dark grey — pure black is invisible on dark theme
        }
    }
}

private let exerciseRegex: NSRegularExpression = {
    // "4×10", "3 x 8", "3×30 sec"
    try! NSRegularExpression(pattern: #"(\d+)\s*[×xX]\s*(\d+)(\s*sec)?"#)
}()

private let amrapRegex: NSRegularExpression = {
    // "3×AMRAP", "3 x MAX", "3xmax"
    try! NSRegularExpression(
        pattern: #"(\d+)\s*[×xX]\s*(?:AMRAP|amrap|MAX|max|fail|FAIL)"#
    )
}()

func parseExercise(_ s: String) -> ParsedExercise {
    let ns = s as NSString
    let range = NSRange(location: 0, length: ns.length)

    if let match = exerciseRegex.firstMatch(in: s, range: range) {
        let setsStr = ns.substring(with: match.range(at: 1))
        let repsStr = ns.substring(with: match.range(at: 2))
        let isTime  = match.range(at: 3).location != NSNotFound
        let nameEnd = match.range.location
        let name = ns.substring(to: nameEnd)
            .trimmingCharacters(in: CharacterSet(charactersIn: " —–-:"))
        return ParsedExercise(
            name: name.isEmpty ? s : name,
            sets: Int(setsStr) ?? 1,
            reps: Int(repsStr) ?? 1,
            isTime: isTime,
            isAMRAP: false,
            isBand: looksLikeBand(s)
        )
    }

    // AMRAP / MAX — "Pushups — 3×AMRAP". Sets is explicit, reps is open;
    // we seed with a sensible per-exercise default so the user starts near
    // the right ballpark rather than nudging from 10 every time.
    if let match = amrapRegex.firstMatch(in: s, range: range) {
        let setsStr = ns.substring(with: match.range(at: 1))
        let nameEnd = match.range.location
        let name = ns.substring(to: nameEnd)
            .trimmingCharacters(in: CharacterSet(charactersIn: " —–-:"))
        let resolvedName = name.isEmpty ? s : name
        return ParsedExercise(
            name: resolvedName,
            sets: Int(setsStr) ?? 1,
            reps: defaultAMRAPReps(for: resolvedName),
            isTime: false,
            isAMRAP: true,
            isBand: looksLikeBand(s)
        )
    }

    return ParsedExercise(
        name: s, sets: 1, reps: 1, isTime: false, isAMRAP: false, isBand: looksLikeBand(s)
    )
}

/// True if the exercise mentions a resistance band — covers "band pull-apart",
/// "banded squat", "loop band glute bridge", etc.
func looksLikeBand(_ s: String) -> Bool {
    let n = s.lowercased()
    return n.contains("band") || n.contains("banded") || n.contains("theraband")
}

/// Sensible starting rep count for an AMRAP exercise based on the name.
/// User overrides via the rep ↑/↓ presets — this is just a smarter starting
/// point than a flat 10 for everything.
func defaultAMRAPReps(for name: String) -> Int {
    let n = name.lowercased()

    // Pull patterns are the hardest — fewer reps
    if n.contains("muscle-up") || n.contains("muscle up") { return 3 }
    if n.contains("pull-up") || n.contains("pullup") || n.contains("chin") { return 8 }
    if n.contains("ring row") || n.contains("inverted row") { return 10 }

    // Push patterns
    if n.contains("hspu") || n.contains("handstand") { return 5 }
    if n.contains("dip") { return 10 }
    if n.contains("ring push") || n.contains("decline push") { return 12 }
    if n.contains("push") { return 20 }       // standard pushups

    // Lower body bodyweight
    if n.contains("pistol") || n.contains("shrimp") { return 5 }
    if n.contains("split squat") || n.contains("bulgarian") { return 12 }
    if n.contains("squat") { return 25 }      // bodyweight squat / air squat
    if n.contains("lunge") { return 16 }      // 8 per side
    if n.contains("bridge") || n.contains("hip thrust") { return 15 }
    if n.contains("calf raise") { return 20 }

    // Conditioning
    if n.contains("burpee") { return 12 }
    if n.contains("mountain climb") { return 30 }
    if n.contains("jumping jack") { return 40 }
    if n.contains("kettlebell swing") || n.contains("kb swing") { return 20 }
    if n.contains("box jump") || n.contains("step up") { return 12 }

    // Core
    if n.contains("crunch") || n.contains("sit-up") || n.contains("situp") { return 20 }
    if n.contains("leg raise") || n.contains("toes to bar") || n.contains("knee raise") { return 12 }
    if n.contains("v-up") || n.contains("v up") { return 12 }

    // Generic AMRAP fallback
    return 10
}

/// Warm-up weights as a function of the working weight, in the user's unit.
/// Single warm-up at 50% for moderate loads; two warm-ups (50% + 75%) for
/// heavier compounds. Rounded to the unit's small-step grid.
func warmupSuggestions(workingWeight: Double, unit: WorkoutUnit) -> [Double] {
    let lightThreshold: Double = unit == .pounds ? 50 : 25
    let heavyThreshold: Double = unit == .pounds ? 95 : 45
    if workingWeight < lightThreshold { return [] }
    let step = unit.smallStep
    let half = (workingWeight * 0.5 / step).rounded() * step
    if workingWeight < heavyThreshold { return [half] }
    let threeQuarter = (workingWeight * 0.75 / step).rounded() * step
    return [half, threeQuarter]
}

/// Sensible starting weight per exercise based on the name. Used only when
/// there's no remembered weight from a prior session — once you log a set,
/// that becomes the new default. Bodyweight stays bodyweight; common lifts
/// start at sane plate-friendly values rather than 0.
func defaultWeight(for name: String) -> Double {
    // Library lookup first — exact match by canonical key. Only honour the
    // bundled default for free-weight entries; "band"/"time"/"amrap" modes
    // don't carry a meaningful pound figure.
    let key = exerciseKey(name)
    if let e = ExerciseLibrary.shared[key], e.mode == "free",
       let lb = e.default_weight_lb {
        return lb
    }

    let n = name.lowercased()

    // Bodyweight — explicit no-load
    let bwTokens = [
        "push", "pull-up", "pullup", "chin", "dip", "plank", "side plank",
        "hang", "knee raise", "leg raise", "flow", "yoga", "mobility",
        "stretch", "warm", "warmup", "warm-up", "warm up", "foam",
        "bird dog", "bird-dog", "dead bug", "deadbug", "crawl",
        "walking", "march", "calf raise", "glute bridge", "single leg bridge",
        "shoulder taps", "scapular", "wall slide", "couch stretch",
        "90/90", "happy baby", "child's pose", "downward",
        "(bw)", "bodyweight",
    ]
    if bwTokens.contains(where: { n.contains($0) }) { return 0 }

    // Heavy compounds — one plate each side ≈ 135 lb
    if n.contains("deadlift") || n.contains("trap bar") { return 135 }
    if n.contains("back squat") || (n.contains("squat") && !n.contains("goblet")
                                                       && !n.contains("split")) {
        return 135
    }
    if n.contains("bench") { return 95 }

    // Hinges and presses
    if n.contains("hip thrust") { return 95 }
    if n.contains("rdl") || n.contains("romanian") { return 65 }
    if n.contains("overhead press") || n.contains("ohp") { return 65 }
    if n.contains("press") { return 45 }   // accessory press

    // Rows + carries + dumbbell work
    if n.contains("row") { return 35 }
    if n.contains("farmer") || n.contains("carry") { return 35 }
    if n.contains("goblet") || n.contains("split squat") { return 25 }
    if n.contains("lunge") { return 20 }

    // Accessories — small dumbbells
    if n.contains("curl") || n.contains("raise") || n.contains("extension")
        || n.contains("fly") || n.contains("rear delt") {
        return 15
    }

    return 0
}

func exerciseKey(_ raw: String) -> String {
    raw.lowercased()
       .components(separatedBy: CharacterSet.alphanumerics.inverted)
       .filter { !$0.isEmpty }
       .joined(separator: "_")
       .prefix(60).description
}
