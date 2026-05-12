import SwiftUI
import UIKit

/// Low-contrast text link below the Start pill. Long-press 2.0 s to commit;
/// the link visually fills with cyan from left to right as you hold. Release
/// before completion cancels (with a soft spring-back). On completion the
/// `onCommit` callback fires — the parent is responsible for showing the
/// reason picker (the unified `DeviationSheet` with `.didSkip` pre-selected).
struct SkipWorkoutButton: View {

    let onCommit: () -> Void

    @State private var pressProgress: Double = 0

    private let holdDuration: Double = 2.0

    init(onCommit: @escaping () -> Void = {}) {
        self.onCommit = onCommit
    }

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                Capsule()
                    .fill(Color.cyan.opacity(0.18))
                    .frame(width: geo.size.width * pressProgress)
            }
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                Text("hold to skip today")
            }
            .font(.caption2.italic())
            .foregroundStyle(.white.opacity(0.4))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 26)
        .background(Color.white.opacity(0.03), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
        .contentShape(Capsule())
        .onLongPressGesture(
            minimumDuration: holdDuration,
            maximumDistance: .infinity,
            perform: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onCommit()
                // The fill is already at 1.0 from the press animation;
                // let it linger briefly so the user registers completion,
                // then fade it out.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.4)) { pressProgress = 0 }
                }
            },
            onPressingChanged: { isPressing in
                if isPressing {
                    withAnimation(.linear(duration: holdDuration)) {
                        pressProgress = 1.0
                    }
                } else {
                    // Release (or cancel by drag/scroll) — spring the fill back.
                    withAnimation(.easeOut(duration: 0.25)) {
                        pressProgress = 0
                    }
                }
            }
        )
    }
}
