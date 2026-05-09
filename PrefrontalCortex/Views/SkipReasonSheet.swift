import SwiftUI

/// Modal showing the 6 preset reasons when the user holds-skip on the
/// SkipWorkoutButton. Tap a chip → fires the closure → caller persists +
/// dismisses + refreshes streak/achievements.
struct SkipReasonSheet: View {

    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let reasons: [String] = [
        "Sick", "Traveling", "Busy", "Unmotivated", "Injury", "Scheduled rest",
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Why are you skipping today?")
                    .font(.body.italic())
                    .foregroundStyle(.white)
                Text("Logged for the adaptive engine — patterns matter more than perfect days.")
                    .font(.caption2.italic())
                    .foregroundStyle(.secondary)
                ReasonFlowLayout(spacing: 10) {
                    ForEach(reasons, id: \.self) { r in
                        Button {
                            onPick(r)
                            dismiss()
                        } label: {
                            Text(r)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.cyan.opacity(0.13),
                                            in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.4)))
                        }
                        .buttonStyle(LivePressStyle())
                    }
                }
                Spacer()
            }
            .padding(20)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Skip today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct ReasonFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
