import SwiftUI

/// Sheet for committing a new Stake. The user types what they'll do
/// ("Cook dinner without my phone"), picks a witness from reach_out,
/// optionally shares the message via the system share sheet, then we
/// persist as `.declared` (if shared) or `.pending` (if dismissed).
///
/// The witness picker pulls from `bundle.social.reach_out` because
/// those are the people the engine already thinks you owe a touchpoint
/// to. Two birds: a real human witness AND a nudge toward the
/// connection the social-graph pipeline already flagged.
struct StakeSheet: View {
    let people: [SocialPerson]
    let band: TimeBand
    var onCommit: (Stake) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String = ""
    @State private var witness: SocialPerson?
    @State private var shareText: String? = nil
    @FocusState private var promptFocused: Bool

    private var canCommit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && witness != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What will you do?") {
                    TextField("Cook dinner without my phone", text: $prompt, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($promptFocused)
                    Text("In the \(band.tag.lowercased()) band — through \(deadlineLabel).")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Section("Who will know?") {
                    if people.isEmpty {
                        Text("No reach-out queue yet. Run the social-media-graph pipeline to populate it.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(people, id: \.id) { p in
                            Button {
                                witness = p
                            } label: {
                                HStack {
                                    Image(systemName: witness?.id == p.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(witness?.id == p.id ? .cyan : .secondary)
                                    Text(p.name ?? "Unknown")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if let days = p.days_since_last {
                                        Text("\(days)d")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Text("The outcome can't be pre-secured because the witness exists.")
                        .font(.footnote.italic())
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Stake it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tell them") { commit() }
                        .disabled(!canCommit)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { promptFocused = true }
            .sheet(isPresented: shareBinding) {
                if let msg = shareText {
                    ActivityViewController(items: [msg])
                }
            }
        }
    }

    private var shareBinding: Binding<Bool> {
        Binding(
            get: { shareText != nil },
            set: { if !$0 { shareText = nil; dismiss() } }
        )
    }

    private var deadlineLabel: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: TimeBand.nextEdge())
    }

    private func commit() {
        guard let w = witness else { return }
        let now = Date()
        let stake = Stake(
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            witnessName: w.name ?? "Friend",
            bandRaw: band.rawValue,
            deadline: TimeBand.nextEdge(),
            createdAt: now,
            declaredAt: nil,
            resolvedAt: nil,
            status: .pending
        )
        StakeStore.save(stake)
        onCommit(stake)
        // Compose the share message — user picks iMessage / SMS / etc.
        shareText = "Stake: I'm going to \(stake.prompt) by \(deadlineLabel). Tell me later if I did."
        // Once shared, the share sheet's dismiss path marks declared.
        markDeclared(stake)
    }

    private func markDeclared(_ stake: Stake) {
        var s = stake
        s.declaredAt = Date()
        s.status = .declared
        StakeStore.save(s)
    }
}

/// UIKit ActivityViewController wrapper. SwiftUI's ShareLink is iOS 16+
/// but text-only and a bit clumsy for our message; this gives us the
/// classic share-sheet UX.
private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
