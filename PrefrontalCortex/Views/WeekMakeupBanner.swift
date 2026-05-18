import SwiftUI

/// Now-tab banner shown when the engine made up (or dropped) a skipped
/// session this week. Auto-applied + reversible: [Keep] dismisses
/// locally; [Undo] re-emits the skip with lock_in=true (the pipeline
/// derivation filters those out, so the make-up disappears next refresh).
struct WeekMakeupBanner: View {
    let makeup: WeekMakeup
    var onKeep: () -> Void
    var onUndo: () -> Void

    private var line: String {
        let s = makeup.skipped?.first
        let what = s?.session ?? "a session"
        if makeup.dropped == true {
            let rest = makeup.next_rest ?? "the week's end"
            return "Skipped \(what) — couldn't be made up before \(rest). Dropped."
        }
        let days = (makeup.recipients ?? []).joined(separator: " · ")
        let rest = makeup.next_rest.map { " before \($0) rest" } ?? ""
        return "Week adjusted — you skipped \(what). Making it up across \(days)\(rest)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WEEK ADJUSTED")
                .font(.caption2.monospaced().bold())
                .tracking(2)
                .foregroundStyle(.cyan)
            Text(line)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if makeup.dropped != true {
                HStack(spacing: 10) {
                    Button("Keep", action: onKeep)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button("Undo", action: onUndo)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.cyan)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.6))
        .background(.black.opacity(0.3))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.cyan.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
