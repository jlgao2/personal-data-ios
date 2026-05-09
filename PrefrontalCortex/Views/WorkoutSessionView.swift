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

    @ViewBuilder
    private func exerciseCard(parsed: ParsedExercise, key: String) -> some View {
        let entries = sets[key] ?? []
        let unitLabel = parsed.isTime ? "sec" : "reps"
        let doneCount = entries.filter { $0.completed }.count

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
            Text("Target \(parsed.sets) × \(parsed.reps) \(unitLabel)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

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
        VStack(spacing: 14) {
            HStack {
                Text("SET \(index + 1)")
                    .font(.caption2.monospaced().bold())
                    .tracking(2)
                    .foregroundStyle(.cyan)
                Spacer()
                Button {
                    withAnimation { focused = nil }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(LivePressStyle())
            }

            paddleControl(label: "WEIGHT",
                          value: entry.weight,
                          unit: "lb",
                          step: 5,
                          format: "%g",
                          onMinus: { adjustWeight(key: key, index: index, by: -5) },
                          onPlus:  { adjustWeight(key: key, index: index, by:  5) })

            paddleControl(label: unitLabel.uppercased(),
                          value: Double(entry.reps),
                          unit: unitLabel,
                          step: 1,
                          format: "%.0f",
                          onMinus: { adjustReps(key: key, index: index, by: -1) },
                          onPlus:  { adjustReps(key: key, index: index, by:  1) })

            Button { markComplete(key: key, index: index) } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Mark complete")
                    Image(systemName: "arrow.right")
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.cyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.cyan.opacity(0.4)))
            }
            .buttonStyle(LivePressStyle())
            .sensoryFeedback(.success, trigger: entry.completed)
        }
        .padding(10)
        .background(Color.cyan.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.cyan.opacity(0.25)))
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
            let memory = UserDefaults.standard.double(forKey: weightMemoryKey(for: key))
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
}

private let exerciseRegex: NSRegularExpression = {
    // "4×10", "3 x 8", "3×30 sec"
    try! NSRegularExpression(pattern: #"(\d+)\s*[×xX]\s*(\d+)(\s*sec)?"#)
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
            isTime: isTime
        )
    }
    return ParsedExercise(name: s, sets: 1, reps: 1, isTime: false)
}

func exerciseKey(_ raw: String) -> String {
    raw.lowercased()
       .components(separatedBy: CharacterSet.alphanumerics.inverted)
       .filter { !$0.isEmpty }
       .joined(separator: "_")
       .prefix(60).description
}
