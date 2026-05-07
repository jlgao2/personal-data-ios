import SwiftUI

struct TransportSettingsView: View {
    @ObservedObject var settings: TransportSettings = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput: String = ""
    @State private var tokenInput: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var saveError: String?

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
