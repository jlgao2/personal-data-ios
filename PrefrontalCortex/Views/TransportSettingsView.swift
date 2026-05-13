import SwiftUI

struct TransportSettingsView: View {
    @ObservedObject var settings: TransportSettings = .shared
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput: String = ""
    @State private var tokenInput: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var saveError: String?
    @AppStorage("workout_unit") private var unitRaw: String = WorkoutUnit.pounds.rawValue
    /// Hide the "MED WATCH" card + the Profile-tab drug-class reference unless
    /// the user has opted in. Off by default — useful only for users who pull
    /// MyChart bundles, otherwise it's noise.
    @AppStorage("med_alerts_enabled") private var medAlertsEnabled: Bool = false

    enum TestStatus {
        case idle
        case testing
        case ok(String)
        case fail(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Laptop URL") {
                    TextField("http://192.168.1.42:8787", text: $urlInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Text("Find with `ipconfig getifaddr en0` on the laptop. Same Wi-Fi only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("Bearer token") {
                    TextField("Run `pipeline/ios_serve.sh` to print it", text: $tokenInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.caption.monospaced())
                }
                Section {
                    Button("Test connection") { Task { await runTest() } }
                        .disabled(URL(string: urlInput) == nil)
                    statusRow
                }
                Section("Workout units") {
                    Picker("Unit", selection: $unitRaw) {
                        ForEach(WorkoutUnit.allCases) { u in
                            Text(u.label).tag(u.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Affects all weights, defaults, warm-up suggestions, and increments in the workout tracker.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("Features") {
                    Toggle("Med watch", isOn: $medAlertsEnabled)
                    Text("Surface the MED WATCH card on the Now tab + drug-class reference on Profile. Only useful if you sync MyChart bundles to the laptop.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Laptop sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                urlInput = settings.serverURLString ?? ""
                tokenInput = settings.token ?? ""
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .testing:
            HStack { ProgressView(); Text("Testing…") }
        case .ok(let info):
            Label(info, systemImage: "checkmark.seal").foregroundStyle(.green)
        case .fail(let msg):
            Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private func runTest() async {
        testStatus = .testing
        guard let baseURL = URL(string: urlInput.trimmingCharacters(in: .whitespaces)) else {
            testStatus = .fail("Invalid URL")
            return
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/health"))
        req.timeoutInterval = 5
        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespaces)
        if !trimmedToken.isEmpty {
            req.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                testStatus = .fail("Non-HTTP response")
                return
            }
            guard http.statusCode == 200 else {
                testStatus = .fail("HTTP \(http.statusCode)")
                return
            }
            let h = try JSONDecoder().decode(HealthResponse.self, from: data)
            testStatus = .ok("OK — bundle: \(h.bundle_mtime ?? "none yet")")
        } catch {
            testStatus = .fail(error.localizedDescription)
        }
    }

    private func save() {
        do {
            try settings.update(serverURLString: urlInput, token: tokenInput)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
