import SwiftUI

/// "Did this instead" — log an actual workout that overrides today's
/// prescribed Day-N session. POSTs to /v1/sessions; the laptop picks it up
/// on its next refresh and the adaptive engine sees it as `workouts_today`.
struct LogSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    @State private var sport: Sport = .cycling
    @State private var durationMin: Int = 30
    @State private var rpe: Double = 6
    @State private var note: String = ""
    @State private var status: SubmitStatus = .idle

    enum Sport: String, CaseIterable, Identifiable {
        case cycling = "CYCLING"
        case running = "RUNNING"
        case lifting = "STRENGTH_TRAINING"
        case yoga    = "YOGA"
        case swimming = "SWIMMING"
        case hiking  = "HIKING"
        case walking = "WALKING"
        case skiing  = "ALPINE_SKIING"
        case other   = "OTHER"

        var id: String { rawValue }
        var label: String {
            rawValue.replacingOccurrences(of: "_", with: " ")
                    .lowercased().capitalized
        }
    }

    enum SubmitStatus {
        case idle, sending
        case ok(String)
        case fail(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sport") {
                    Picker("", selection: $sport) {
                        ForEach(Sport.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxHeight: 130)
                }
                Section("Duration") {
                    Stepper(value: $durationMin, in: 5...360, step: 5) {
                        Text("\(durationMin) min")
                            .font(.body.monospaced())
                    }
                }
                Section("Effort (RPE 1–10)") {
                    HStack {
                        Slider(value: $rpe, in: 1...10, step: 1)
                        Text("\(Int(rpe))")
                            .font(.body.monospaced())
                            .foregroundStyle(rpeColor)
                            .frame(width: 28)
                    }
                }
                Section("Note (optional)") {
                    TextField("e.g., easy spin commute, bad knee day…", text: $note,
                              axis: .vertical)
                        .lineLimit(2...4)
                }
                if !isIdle {
                    Section { statusLine }
                }
            }
            .navigationTitle("Log what I did")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { Task { await submit() } }
                        .disabled(isSending)
                }
            }
        }
    }

    private var rpeColor: Color {
        if rpe >= 8 { return .red }
        if rpe >= 6 { return .orange }
        if rpe >= 4 { return .cyan }
        return .green
    }

    private var isSending: Bool {
        if case .sending = status { return true } else { return false }
    }

    private var isIdle: Bool {
        if case .idle = status { return true } else { return false }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:        EmptyView()
        case .sending:     HStack { ProgressView(); Text("Logging…") }
        case .ok(let m):   Label(m, systemImage: "checkmark.seal").foregroundStyle(.green)
        case .fail(let m): Label(m, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private func submit() async {
        status = .sending
        let row = SessionUpload(
            client_id:    UUID().uuidString,
            ts:           ISO8601DateFormatter().string(from: Date()),
            sport:        sport.rawValue,
            duration_min: durationMin,
            rpe:          Int(rpe),
            note:         note
        )
        do {
            let resp = try await TransportClient.shared.uploadSessions([row])
            status = .ok("Logged (\(resp.written) row)")
            store.lastUploadResult = "Session logged: \(sport.label) · \(durationMin) min"
            // Brief confirmation, then dismiss.
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        } catch {
            status = .fail(TransportClient.wrap(error).localizedDescription)
        }
    }
}
