import SwiftUI

/// Slow-drifting, low-contrast radial gradients on a black ground.
/// Two counter-phased blobs (cyan + indigo) rotate on different periods
/// so the field never quite repeats. Deliberately subtle — this is the
/// breath of the screen, not a feature.
struct AnimatedAuraBackground: View {
    var body: some View {
        // Qualified — codebase's chronological `TimelineView` shadows SwiftUI's.
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase1 = t * 2 * .pi / 42  // 42s loop
            let phase2 = t * 2 * .pi / 67  // 67s loop, irrational ratio so it doesn't repeat

            ZStack {
                Color.black

                RadialGradient(
                    colors: [
                        Color.cyan.opacity(0.14),
                        Color.cyan.opacity(0.04),
                        .clear,
                    ],
                    center: UnitPoint(
                        x: 0.5 + 0.32 * cos(phase1),
                        y: 0.32 + 0.18 * sin(phase1)
                    ),
                    startRadius: 60,
                    endRadius: 460
                )

                RadialGradient(
                    colors: [
                        Color.indigo.opacity(0.16),
                        Color.indigo.opacity(0.04),
                        .clear,
                    ],
                    center: UnitPoint(
                        x: 0.42 - 0.28 * cos(phase2),
                        y: 0.72 + 0.18 * sin(phase2)
                    ),
                    startRadius: 80,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
    }
}
