import SwiftUI

struct TransportSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workout_unit") private var unitRaw: String = WorkoutUnit.pounds.rawValue
    @AppStorage("med_alerts_enabled") private var medAlertsEnabled: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud sync") {
                    HStack {
                        Text("Container")
                        Spacer()
                        Text(iCloudPaths.isAvailable ? "Available" : "Not signed in")
                            .foregroundStyle(.secondary)
                    }
                    if let m = store.manifest {
                        HStack {
                            Text("Last manifest")
                            Spacer()
                            Text(m.exported_at).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack {
                            Text("Pipeline")
                            Spacer()
                            Text(m.pipeline_version).foregroundStyle(.secondary)
                        }
                    }
                    Button("Force re-download") {
                        Task { await store.applyLatestManifest() }
                    }
                }
                Section("Workout units") {
                    Picker("Unit", selection: $unitRaw) {
                        ForEach(WorkoutUnit.allCases) { u in
                            Text(u.label).tag(u.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Features") {
                    Toggle("Med watch", isOn: $medAlertsEnabled)
                }
                Section("Day") {
                    Button("Tick day over") {
                        store.tickDayOver()
                        dismiss()
                    }
                    Text("Force today's date-derived views (lock dots, session card, timeline) to re-evaluate from the current `Date()`. Useful when the app was left open across midnight and yesterday's state is still showing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("Config") {
                    NavigationLink("Backups & reset") { ConfigRecoveryView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// Temporary placeholder — replaced by the real ConfigRecoveryView in Task 21.
struct ConfigRecoveryView: View {
    var body: some View {
        Text("Backups & reset coming soon.")
            .foregroundStyle(.secondary)
            .padding()
    }
}
