import SwiftUI

struct ConfigRecoveryView: View {
    @State private var backups: [String] = []
    @State private var resetConfirmText: String = ""
    @State private var showFactoryAlert = false

    var body: some View {
        Form {
            Section("Backups") {
                if backups.isEmpty {
                    Text("No backups yet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(backups, id: \.self) { id in
                    Button(id) { Task { await restore(id) } }
                }
            }
            Section("Factory reset") {
                TextField("Type \"reset\" to enable", text: $resetConfirmText)
                Button("Reset to seed config") { showFactoryAlert = true }
                    .disabled(resetConfirmText != "reset")
                    .foregroundStyle(resetConfirmText == "reset" ? .red : .gray)
            }
        }
        .navigationTitle("Backups & reset")
        .onAppear {
            backups = (try? iCloudTransport.shared.listBackups()) ?? []
        }
        .alert("Reset config?", isPresented: $showFactoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task { await factoryReset() }
            }
        } message: {
            Text("This replaces your config with bundled defaults. The current state is snapshotted to a backup first.")
        }
    }

    private func restore(_ id: String) async {
        try? await iCloudTransport.shared.restoreBackup(id)
    }
    private func factoryReset() async {
        guard let configDir = iCloudPaths.configDir else { return }
        for name in ["health_profile.json", "exercise_library.json"] {
            guard let src = Bundle.main.url(forResource: name, withExtension: nil,
                                            subdirectory: "seeds") else { continue }
            let dest = configDir.appendingPathComponent(name)
            _ = try? FileManager.default.replaceItemAt(dest, withItemAt: src)
        }
    }
}
