import SwiftUI

/// Per-day editor for the user's weekly rhythm. Seven rows — Mon
/// through Sun — each row has a kind picker + freeform anchor text
/// field. Save writes to iCloud config/weekly_rhythm.json via
/// WeeklyRhythmStore; the laptop pipeline reads it on its next refresh
/// and adjusts the daily_protocol map.
///
/// Kinds are free-form strings — the picker surfaces presets but the
/// user can type any string and the pipeline is responsible for
/// normalisation. The anchor field is also free-form ("improv 8pm",
/// "travel — Tokyo", "PT 4pm"); empty = no anchor.
struct WeeklyRhythmEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rhythm: WeeklyRhythm = .empty()
    @State private var loading: Bool = true
    @State private var saving: Bool = false
    @State private var saveError: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading rhythm…")
                } else {
                    Form {
                        Section {
                            Text("Pick the shape of each weekday. Kind is free-form — the picker is suggestions only. Anchor names a specific commitment that day (\u{201C}improv 8pm\u{201D}, \u{201C}travel — Tokyo\u{201D}). Save writes to iCloud; the laptop picks it up on next refresh.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(WeeklyRhythm.dayKeys, id: \.self) { key in
                            dayRow(key: key)
                        }
                        if let saveError {
                            Section { Text(saveError).foregroundStyle(.red) }
                        }
                    }
                }
            }
            .navigationTitle("Weekly rhythm")
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
    private func dayRow(key: String) -> some View {
        let binding = Binding<WeeklyRhythm.DayConfig>(
            get: { rhythm.config(for: key) },
            set: { rhythm.days[key] = $0 }
        )
        Section(WeeklyRhythm.dayLabel(key)) {
            HStack {
                Text("Kind")
                Spacer()
                Menu {
                    ForEach(WeeklyRhythm.kindPresets, id: \.self) { preset in
                        Button(preset) {
                            var c = binding.wrappedValue
                            c.kind = preset
                            binding.wrappedValue = c
                        }
                    }
                } label: {
                    Text(binding.wrappedValue.kind)
                        .foregroundStyle(.white)
                }
            }
            TextField("Custom kind", text: Binding(
                get: { binding.wrappedValue.kind },
                set: { binding.wrappedValue.kind = $0 }
            ))
            .disableAutocorrection(true)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            TextField("Anchor (optional)", text: Binding(
                get: { binding.wrappedValue.anchor ?? "" },
                set: {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    binding.wrappedValue.anchor = trimmed.isEmpty ? nil : trimmed
                }
            ))
        }
    }

    private func reload() async {
        rhythm = await WeeklyRhythmStore.load()
        loading = false
    }

    private func save() async {
        saving = true
        saveError = nil
        do {
            try await WeeklyRhythmStore.save(rhythm)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        saving = false
    }
}
