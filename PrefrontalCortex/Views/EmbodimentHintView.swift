import SwiftUI

/// Evening-band card prompting a short embodiment practice — stretch,
/// breath, walk, anything that gets the user back into their body after
/// a day spent in head-space. The hint rotates deterministically by
/// date so the same prompt doesn't repeat for stretches; tap to mark
/// done (DailyLock-stored, resets at midnight) for a small chime of
/// completion satisfaction without bloating the streak gate.
///
/// Intentionally minimal — three rotating prompts, one tap. The
/// philosophy is "you don't need an app to breathe; you just need a
/// nudge to remember to."
struct EmbodimentHintView: View {
    @State private var done: Bool = false
    @State private var refreshTick: Int = 0

    private static let prompts: [(symbol: String, text: String)] = [
        ("wind", "Three slow breaths. Notice where you're holding tension."),
        ("figure.walk.motion", "Walk one minute — no phone, no podcast."),
        ("figure.flexibility", "Stretch the part of you that aches most."),
        ("face.smiling", "Look at one thing in the room for thirty seconds."),
        ("hands.sparkles", "Wash your hands slowly. Feel the water temperature."),
    ]

    private var prompt: (symbol: String, text: String) {
        let cal = Calendar.current
        let day = cal.component(.day, from: Date())
        return Self.prompts[day % Self.prompts.count]
    }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : prompt.symbol)
                    .font(.title3)
                    .foregroundStyle(done ? .green : .indigo)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("EMBODIMENT")
                        .font(.caption2.monospaced().bold())
                        .tracking(2)
                        .foregroundStyle(done ? .green : .indigo)
                    Text(prompt.text)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(done ? 0.45 : 0.85))
                        .strikethrough(done, color: .white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder((done ? Color.green : Color.indigo).opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .id(refreshTick)
        .onAppear { done = Self.loadDone() }
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in
            done = Self.loadDone()
            refreshTick += 1
        }
    }

    private func toggle() {
        done.toggle()
        Self.saveDone(done)
    }

    private static func key() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "embodiment_done_\(f.string(from: Date()))"
    }
    private static func loadDone() -> Bool {
        UserDefaults.standard.bool(forKey: key())
    }
    private static func saveDone(_ done: Bool) {
        if done {
            UserDefaults.standard.set(true, forKey: key())
        } else {
            UserDefaults.standard.removeObject(forKey: key())
        }
    }
}
