import SwiftUI

/// Slow-drifting radial gradients on a black ground, with a quiet starfield
/// twinkling overhead. Two counter-phased blobs (cyan + indigo) rotate on
/// different periods so the field never quite repeats. The stars are seeded
/// once per layout so they stay still while their brightness pulses on
/// independent phases. Deliberately quiet — felt, not seen.
struct AnimatedAuraBackground: View {
    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase1 = t * 2 * .pi / 42  // 42s loop
            let phase2 = t * 2 * .pi / 67  // 67s loop, irrational ratio so it doesn't repeat

            ZStack {
                Color.black

                RadialGradient(
                    colors: [
                        Color.cyan.opacity(0.16),
                        Color.cyan.opacity(0.05),
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
                        Color.indigo.opacity(0.18),
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

                Starfield(now: t)
            }
        }
        .ignoresSafeArea()
    }
}

/// Quiet starfield. ~80 stars at fixed positions seeded by a constant; each
/// one pulses brightness on its own phase. No motion (parallax felt cheap),
/// just slow shimmer.
private struct Starfield: View {
    let now: TimeInterval

    private static let stars: [Star] = {
        var rng = SeededRNG(seed: 4242)
        return (0..<90).map { _ in
            Star(
                x: rng.next01(),
                y: rng.next01(),
                radius: rng.next(in: 0.4...1.6),
                baseAlpha: rng.next(in: 0.18...0.65),
                phase: rng.next(in: 0...(2 * .pi)),
                period: rng.next(in: 4...11)
            )
        }
    }()

    var body: some View {
        Canvas { ctx, size in
            for s in Self.stars {
                let pulse = (sin(now * 2 * .pi / s.period + s.phase) + 1) / 2
                let alpha = s.baseAlpha * (0.55 + 0.45 * pulse)
                let center = CGPoint(x: s.x * size.width, y: s.y * size.height)
                let rect = CGRect(
                    x: center.x - s.radius, y: center.y - s.radius,
                    width: s.radius * 2, height: s.radius * 2
                )
                let shading = GraphicsContext.Shading.color(.white.opacity(alpha))
                ctx.fill(Path(ellipseIn: rect), with: shading)
                // Soft halo around brighter stars
                if s.baseAlpha > 0.45 && pulse > 0.6 {
                    let haloRect = rect.insetBy(dx: -s.radius * 1.6, dy: -s.radius * 1.6)
                    ctx.fill(
                        Path(ellipseIn: haloRect),
                        with: .color(.white.opacity(alpha * 0.18))
                    )
                }
            }
        }
        .blendMode(.screen)
    }
}

private struct Star {
    let x: Double      // 0..1
    let y: Double      // 0..1
    let radius: Double // points
    let baseAlpha: Double
    let phase: Double  // radians
    let period: Double // seconds
}

/// Tiny linear-congruential RNG so star positions are deterministic across
/// rebuilds. Avoids the SwiftUI body-recomputation problem with `.random()`.
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func next01() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * next01()
    }
}
