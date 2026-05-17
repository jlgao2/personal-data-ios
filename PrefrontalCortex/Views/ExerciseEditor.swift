import SwiftUI

/// Plan-tab card → sheet for editing the prescribed training protocol
/// per day/section. This is the end-user path for "add glute medius to
/// Day 1 prehab" — no JSON hand-editing. Writes
/// config/protocol_overrides.json to iCloud; the laptop merges it on
/// next refresh (Python reader is the same follow-up as rhythm/supps).
struct ExerciseEditorCard: View {
    /// The pipeline-generated baseline, passed from PlanTabView so the
    /// editor seeds each section from what's actually prescribed today
    /// rather than a blank slate.
    let dailyProtocol: [String: DayProtocol]?

    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PRESCRIBED EXERCISES")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .tracking(2)
                    Text("Edit prehab / warmup / main / core per day")
                        .font(.footnote.italic())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) {
            ExerciseEditorSheet(dailyProtocol: dailyProtocol ?? [:])
        }
    }
}

struct ExerciseEditorSheet: View {
    let dailyProtocol: [String: DayProtocol]

    @Environment(\.dismiss) private var dismiss
    @State private var override: ProtocolOverride = .empty
    @State private var loading = true
    @State private var saving = false
    @State private var saveError: String?
    @State private var day: String = "Day 1"
    /// Working copy: dayKey → section → lines. Seeded from override (if
    /// the user has edited before) else the pipeline baseline.
    @State private var working: [String: [String: [String]]] = [:]

    private static let sections = ["rehab", "warmup", "main", "core"]

    private var dayKeys: [String] {
        dailyProtocol.keys.sorted {
            (Int($0.split(separator: " ").last ?? "0") ?? 0)
                < (Int($1.split(separator: " ").last ?? "0") ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading protocol…")
                } else {
                    Form {
                        Section {
                            Picker("Day", selection: $day) {
                                ForEach(dayKeys, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            Text("Edits replace that section for that day. Saved to iCloud; the laptop merges it on next refresh.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Self.sections, id: \.self) { sec in
                            sectionEditor(sec)
                        }
                        if let saveError {
                            Section { Text(saveError).foregroundStyle(.red) }
                        }
                    }
                }
            }
            .navigationTitle("Prescribed exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                        .fontWeight(.semibold)
                }
            }
            .task { await reload() }
        }
    }

    @ViewBuilder
    private func sectionEditor(_ sec: String) -> some View {
        let lines = working[day]?[sec] ?? []
        Section(sec.uppercased()) {
            if lines.isEmpty {
                Text("Empty").font(.footnote.italic()).foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                TextField("Exercise", text: Binding(
                    get: { working[day]?[sec]?[idx] ?? "" },
                    set: { working[day, default: [:]][sec, default: []][idx] = $0 }
                ))
                .font(.callout)
            }
            .onDelete { offs in
                working[day, default: [:]][sec, default: []].remove(atOffsets: offs)
            }
            Button("Add exercise", systemImage: "plus") {
                working[day, default: [:]][sec, default: []].append("")
            }
            .font(.footnote)
        }
    }

    private func baseline(_ d: String, _ sec: String) -> [String] {
        guard let p = dailyProtocol[d] else { return [] }
        switch sec {
        case "rehab":  return p.rehab ?? []
        case "warmup": return p.warmup ?? []
        case "main":   return p.main ?? []
        case "core":   return p.core ?? []
        default:       return []
        }
    }

    private func reload() async {
        override = await ProtocolOverrideStore.load()
        var w: [String: [String: [String]]] = [:]
        for d in dayKeys {
            for sec in Self.sections {
                // Seed from the user's override if present, else the
                // pipeline baseline — so the first edit starts from the
                // real prescription, not blank.
                w[d, default: [:]][sec] = override.list(day: d, section: sec)
                    ?? baseline(d, sec)
            }
        }
        working = w
        if let first = dayKeys.first { day = first }
        loading = false
    }

    private func save() async {
        saving = true
        saveError = nil
        var next = ProtocolOverride.empty
        for d in dayKeys {
            for sec in Self.sections {
                let edited = (working[d]?[sec] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                // Only persist a section as an override when it actually
                // differs from the pipeline baseline — keeps the file to
                // genuine user intent, not a full snapshot.
                if edited != baseline(d, sec) {
                    next.set(day: d, section: sec, edited)
                }
            }
        }
        do {
            try await ProtocolOverrideStore.save(next)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        saving = false
    }
}
