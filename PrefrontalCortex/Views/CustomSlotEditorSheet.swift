import SwiftUI

/// Edit sheet for the user's custom daily lock slots. Lists the
/// built-in slots (read-only — surfaced so the user knows what's
/// already covered without leaving the sheet) above the custom-slot
/// editor.
///
/// Custom slots can be:
///   * Added — name + 2-5 char short label, persisted via CustomSlotStore.upsert
///   * Renamed — tap an existing row → inline fields
///   * Removed — swipe-to-delete on a row
///
/// Built-in slots aren't editable here — they have writer surfaces
/// elsewhere (workout commit, stack toggle, mindful chip) and renaming
/// their UI label would create inconsistencies across surfaces. If the
/// user doesn't want a built-in slot, the path is long-press on the
/// corresponding obligation card → Authorship "From outside", which
/// removes it from the chip entirely.
struct CustomSlotEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [CustomSlot] = CustomSlotStore.load()
    @State private var newLabel: String = ""
    @State private var newFullName: String = ""
    @FocusState private var labelFocused: Bool

    private var canAdd: Bool {
        let l = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = newFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !l.isEmpty && !n.isEmpty && l.count <= 5
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Built-in slots") {
                    Text("Workout · AM supps · PM supps · Mindful eating · Skincare AM · Skincare PM")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("To remove a built-in, long-press its obligation card on the Now tab → \u{201C}From outside\u{201D}.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Your custom slots") {
                    if slots.isEmpty {
                        Text("None yet. Add one below.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(slots) { slot in
                        slotRow(slot)
                    }
                    .onDelete(perform: deleteSlots)
                }

                Section("Add a slot") {
                    TextField("Short label (e.g., MED)", text: $newLabel)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .focused($labelFocused)
                    TextField("Full name (e.g., Meditation)", text: $newFullName)
                    Button("Add") { addSlot() }
                        .disabled(!canAdd)
                }

                Section {
                    Text("Custom slots are tap-to-toggle on the Daily Lock chip and count toward your daily complete. Delete a slot to remove it from the gate.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Daily slots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func slotRow(_ slot: CustomSlot) -> some View {
        let idx = slots.firstIndex(where: { $0.id == slot.id }) ?? 0
        VStack(alignment: .leading, spacing: 4) {
            TextField("Label", text: Binding(
                get: { slots[idx].label },
                set: { slots[idx].label = String($0.prefix(5)).uppercased() }
            ))
            .font(.callout.monospaced().weight(.semibold))
            .textInputAutocapitalization(.characters)
            .disableAutocorrection(true)
            .onSubmit { CustomSlotStore.upsert(slots[idx]) }
            TextField("Full name", text: Binding(
                get: { slots[idx].fullName },
                set: { slots[idx].fullName = $0 }
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .onSubmit { CustomSlotStore.upsert(slots[idx]) }
        }
        .onChange(of: slots[idx]) { _, new in
            CustomSlotStore.upsert(new)
        }
    }

    private func addSlot() {
        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let name  = newFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextOrder = (slots.map(\.order).max() ?? 99) + 1
        let slot = CustomSlot(label: label, fullName: name, order: nextOrder)
        CustomSlotStore.upsert(slot)
        slots = CustomSlotStore.load()
        newLabel = ""
        newFullName = ""
        labelFocused = true
    }

    private func deleteSlots(at offsets: IndexSet) {
        let ids = offsets.map { slots[$0].id }
        for id in ids { CustomSlotStore.remove(id: id) }
        slots = CustomSlotStore.load()
    }
}
