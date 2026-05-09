import SwiftUI

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

    /// exerciseKey → array of SetEntry, one per prescribed set
    @State private var sets: [String: [SetEntry]] = [:]
    /// Currently focused (exercise, set index)
    @State private var focused: Focus? = nil

    struct SetEntry: Codable, Equatable {
        var weight: Double
        var reps: Int
        var completed: Bool
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
        .preferredColorScheme(.dark)
        .onAppear { loadState() }
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
        let warmups = warmupSuggestions(workingWeight: workingWeight)
        if !warmups.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "flame")
                    .font(.caption2)
                Text("warm up: " + warmups.map { "\(Int($0)) × 5" }.joined(separator: ", "))
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

            warmupHint(workingWeight: entries.first?.weight ?? 0)

            // Sets
            VStack(spacing: 6) {
                ForEach(entries.indices, id: \.self) { i in
                    let entry = entries[i]
                    let isFocused = focused == Focus(exerciseKey: key, setIndex: i)
                    if isFocused {
                        activeSetEditor(key: key, index: i, entry: entry, unitLabel: unitLabel)
                    } else {
                        summaryRow(index: i, entry: entry, unitLabel: unitLabel) {
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

    private func activeSetEditor(key: String, index: Int, entry: SetEntry, unitLabel: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("SET \(index + 1)")
                    .font(.caption2.monospaced().bold())
                    .tracking(2)
                    .foregroundStyle(.cyan)
                Spacer()
                Text("base \(formattedWeight(entry.weight)) × \(entry.reps)")
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

            // Reps nudge — small inline ± so user can shape the rep count
            // before tapping a weight preset.
            HStack(spacing: 14) {
                Text(unitLabel.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Spacer()
                repNudgeButton(symbol: "minus") {
                    adjustReps(key: key, index: index, by: -1)
                }
                Text("\(entry.reps)")
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 36)
                    .contentTransition(.numericText(value: Double(entry.reps)))
                repNudgeButton(symbol: "plus") {
                    adjustReps(key: key, index: index, by: 1)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: entry.reps)

            // 4 weight-preset buttons. Each tap = log this set with that weight
            // and advance to the next. One-tap-per-set is the killer move.
            VStack(spacing: 8) {
                presetButton(.bigUp,    key: key, index: index, entry: entry)
                presetButton(.smallUp,  key: key, index: index, entry: entry)
                presetButton(.same,     key: key, index: index, entry: entry)
                presetButton(.down,     key: key, index: index, entry: entry)
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.cyan.opacity(0.25)))
    }

    private enum Preset {
        case bigUp, smallUp, same, down
        var delta: Double {
            switch self {
            case .bigUp:   return 10
            case .smallUp: return 5
            case .same:    return 0
            case .down:    return -5
            }
        }
        var label: String {
            switch self {
            case .bigUp:   return "↑↑  +10"
            case .smallUp: return "↑   +5"
            case .same:    return "=   same"
            case .down:    return "↓   −5"
            }
        }
        var color: Color {
            switch self {
            case .bigUp:   return .green
            case .smallUp: return .cyan
            case .same:    return .white
            case .down:    return .orange
            }
        }
    }

    private func presetButton(_ p: Preset, key: String, index: Int, entry: SetEntry) -> some View {
        let newWeight = max(0, entry.weight + p.delta)
        let isBW = newWeight == 0
        let preview = isBW ? "BW × \(entry.reps)"
                           : "\(formattedWeight(newWeight)) × \(entry.reps)"

        return Button {
            logSetWith(weight: newWeight, key: key, index: index)
        } label: {
            HStack {
                Text(p.label)
                    .font(.body.monospaced().weight(.semibold))
                Spacer()
                Text(preview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(p.color)
            .background(p.color.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(p.color.opacity(0.35)))
        }
        .buttonStyle(LivePressStyle())
        .sensoryFeedback(.success, trigger: entry.completed)
    }

    private func repNudgeButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 38, height: 38)
                .background(Color.cyan.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(Color.cyan.opacity(0.3)))
        }
        .buttonStyle(LivePressStyle())
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

    private func summaryRow(index: Int, entry: SetEntry, unitLabel: String,
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
                    Text("\(formattedWeight(entry.weight)) × \(entry.reps)")
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

    /// Set the weight on this set, then mark it complete (which inherits
    /// values into the next set + advances focus). Used by the 4 weight
    /// preset buttons in the active editor.
    private func logSetWith(weight: Double, key: String, index: Int) {
        guard var arr = sets[key], index < arr.count else { return }
        arr[index].weight = max(0, weight)
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
    }

    private func formattedWeight(_ w: Double) -> String {
        if w == 0 { return "BW" }
        return String(format: "%g lb", w)
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
            // Memory wins; if never logged, fall back to a sensible default
            // for the exercise type (bodyweight = 0, deadlift = 135, etc.).
            let memory: Double
            if let stored = UserDefaults.standard.object(forKey: weightMemoryKey(for: key)) as? Double {
                memory = stored
            } else {
                memory = defaultWeight(for: parsed.name)
            }
            fresh[key] = (0..<parsed.sets).map { _ in
                SetEntry(weight: memory, reps: parsed.reps, completed: false)
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
                return
            }
        }
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

        let row: [String: Any] = [
            "client_id": "\(Self.todayDateString())_\(dayKey)",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "sport": "STRENGTH_TRAINING",
            "duration_min": max(15, total.count * 3),
            "rpe": 6,
            "note": "\(dayLabel) · \(note)",
        ]
        do {
            _ = try await TransportClient.shared.uploadSessions([row])
            store.lastUploadResult = "Workout logged · \(total.count) sets"
        } catch {
            store.lastUploadResult = "Logged locally (laptop unreachable)"
        }
        dismiss()
    }
}

// MARK: - Exercise string parsing

struct ParsedExercise {
    let name: String
    let sets: Int
    let reps: Int
    let isTime: Bool
    let isAMRAP: Bool       // "as many reps as possible" — fluid target
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
            isAMRAP: false
        )
    }

    // AMRAP / MAX — "Pushups — 3×AMRAP". Sets is the explicit number, reps
    // is open-ended — we seed at 10 to give the user something to nudge from.
    if let match = amrapRegex.firstMatch(in: s, range: range) {
        let setsStr = ns.substring(with: match.range(at: 1))
        let nameEnd = match.range.location
        let name = ns.substring(to: nameEnd)
            .trimmingCharacters(in: CharacterSet(charactersIn: " —–-:"))
        return ParsedExercise(
            name: name.isEmpty ? s : name,
            sets: Int(setsStr) ?? 1,
            reps: 10,
            isTime: false,
            isAMRAP: true
        )
    }

    return ParsedExercise(name: s, sets: 1, reps: 1, isTime: false, isAMRAP: false)
}

/// Warm-up weights as a function of the working weight. Single warm-up at
/// 50% for moderate loads; two warm-ups (50% + 75%) for heavier compounds.
/// Rounded to 5 lb to keep the math plate-friendly.
func warmupSuggestions(workingWeight: Double) -> [Double] {
    if workingWeight < 50 { return [] }
    let half = (workingWeight * 0.5 / 5).rounded() * 5
    if workingWeight < 95 { return [half] }
    let threeQuarter = (workingWeight * 0.75 / 5).rounded() * 5
    return [half, threeQuarter]
}

/// Sensible starting weight per exercise based on the name. Used only when
/// there's no remembered weight from a prior session — once you log a set,
/// that becomes the new default. Bodyweight stays bodyweight; common lifts
/// start at sane plate-friendly values rather than 0.
func defaultWeight(for name: String) -> Double {
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
