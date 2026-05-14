import SwiftUI

/// Per-supplement editor for the user's daily stack. Lists current
/// supplements with inline name + dose + timing fields, lets the user
/// add new ones and swipe-delete existing ones, saves to iCloud
/// `config/supplements.json` via `SupplementConfigStore`.
///
/// Two seed modes:
///   * If the user has never edited the stack, the bundle's current
///     `profile.supplement_stack` seeds the editor — so the first edit
///     starts from what the laptop currently prescribes, not blank.
///   * Subsequent edits load from `config/supplements.json` directly.
///
/// The pipeline-side reader of `config/supplements.json` doesn't exist
/// yet (Python follow-up); writes here are still useful as a record of
/// intent and become live once the pipeline reads the file.
struct SupplementEditorSheet: View {
    /// Bundle-side seed used on first edit. Caller passes
    /// `bundle.profile.supplement_stack` so the editor doesn't open
    /// empty when the user hasn't customised yet.
    let seedFromBundle: [Supplement]

    @Environment(\.dismiss) private var dismiss
    @State private var config: SupplementConfig = .empty
    @State private var loading: Bool = true
    @State private var saving: Bool = false
    @State private var saveError: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading stack…")
                } else {
                    Form {
                        Section {
                            Text("Edit your stack. Saved to iCloud — the laptop reads it on next refresh.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Section("Supplements") {
                            if config.supplements.isEmpty {
                                Text("Empty. Add one below.")
                                    .font(.footnote.italic())
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(config.supplements.enumerated()), id: \.element.id) { idx, _ in
                                row(idx: idx)
                            }
                            .onDelete(perform: deleteRows)
                        }
                        Section {
                            Button("Add supplement", systemImage: "plus") { addBlank() }
                        }
                        if let saveError {
                            Section { Text(saveError).foregroundStyle(.red) }
                        }
                    }
                }
            }
            .navigationTitle("Supplement stack")
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
    private func row(idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: Binding(
                get: { config.supplements[idx].name },
                set: { config.supplements[idx] = updated(idx, name: $0) }
            ))
            .font(.callout.weight(.semibold))
            HStack {
                TextField("Dose (e.g. 5g)", text: Binding(
                    get: { config.supplements[idx].dose ?? "" },
                    set: { config.supplements[idx] = updated(idx, dose: $0) }
                ))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                Spacer()
                TextField("Timing", text: Binding(
                    get: { config.supplements[idx].timing ?? "" },
                    set: { config.supplements[idx] = updated(idx, timing: $0) }
                ))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }
        }
    }

    /// Rebuild an immutable Supplement with one field swapped. The
    /// model has a constant `let` for each field, so we can't mutate in
    /// place — this small helper keeps the row-binding code readable.
    private func updated(_ idx: Int,
                         name: String? = nil,
                         dose: String? = nil,
                         timing: String? = nil) -> Supplement {
        let s = config.supplements[idx]
        return Supplement(
            name: name ?? s.name,
            dose: emptyToNil(dose) ?? s.dose,
            timing: emptyToNil(timing) ?? s.timing,
            with_food: s.with_food,
            rationale: s.rationale,
            links: s.links,
            evidence: s.evidence
        )
    }

    private func emptyToNil(_ s: String?) -> String? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func addBlank() {
        config.supplements.append(Supplement(
            name: "New supplement",
            dose: nil,
            timing: "morning",
            with_food: nil,
            rationale: nil,
            links: nil,
            evidence: nil
        ))
    }

    private func deleteRows(at offsets: IndexSet) {
        config.supplements.remove(atOffsets: offsets)
    }

    private func reload() async {
        let loaded = await SupplementConfigStore.load()
        if loaded.supplements.isEmpty && !seedFromBundle.isEmpty {
            // First time the user opens the editor — seed from the
            // bundle's current stack so they're editing the existing
            // prescription, not a blank slate.
            config = SupplementConfig(supplements: seedFromBundle)
        } else {
            config = loaded
        }
        loading = false
    }

    private func save() async {
        saving = true
        saveError = nil
        do {
            try await SupplementConfigStore.save(config)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        saving = false
    }
}
