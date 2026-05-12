import SwiftUI

/// Backdrop for the `.social` tab.
///
/// Personality: nodes / network — flow is biased toward a small set of
/// attractor "hubs" so particles drift between them, drawing the implicit
/// graph of a social network. Curl noise still contributes ~70% so the
/// streams aren't dead-straight, just attracted.
///
/// Palette: cyan → indigo → purple → muted blue. Matches the indigo wash
/// the social pane already used in the MVP graph implementation; this
/// upgrades the visual without re-keying any color tokens.
struct NodesBackground: View {
    var body: some View {
        ZStack {
            Color.black

            // Indigo wash, same temperature as the MVP NodesBackground had,
            // so users notice the new motion but not a palette shift.
            RadialGradient(
                colors: [
                    Color.indigo.opacity(0.22),
                    Color.indigo.opacity(0.05),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.45),
                startRadius: 80,
                endRadius: 560
            )

            FlowFieldCanvas(config: Self.config)
        }
        .ignoresSafeArea()
    }

    /// Deterministic hub positions (in unit-square coords). Five hubs spread
    /// around the frame; particles flow between them weighted by inverse
    /// squared distance. Hand-tuned, not seeded — we want consistent hub
    /// layout across all phones.
    private static let hubs: [(Double, Double)] = [
        (0.22, 0.28),
        (0.78, 0.22),
        (0.50, 0.55),
        (0.18, 0.78),
        (0.82, 0.80),
    ]

    // Hoisted palette — see RiverOfGlowBackground for the rationale.
    private static let palette: [Color] = [
        .cyan,
        .indigo,
        Color.purple.opacity(0.7),
        Color.blue.opacity(0.5),
    ]

    private static let config = FlowFieldConfig(
        particleCount: 500,
        trailCapacity: 18,
        minLifespan: 5.0,
        maxLifespan: 9.5,
        velocityLerp: 0.12,
        speed: 0.0030,
        palette: NodesBackground.palette,
        // 30% attractor force + 70% curl noise. The attractor sum is taken
        // weighted by 1/d² (clamped) and normalized so the result is roughly
        // unit-length; without normalization, particles inside a hub would
        // get sucked in infinitely.
        flowAt: { x, y, t in
            // Attractor field — sum of inverse-square pulls toward each hub.
            var ax = 0.0
            var ay = 0.0
            for h in NodesBackground.hubs {
                let dx = h.0 - x
                let dy = h.1 - y
                let d2 = max(dx * dx + dy * dy, 0.005)  // floor to avoid singularity at hub center
                let w = 1.0 / d2
                ax += dx * w
                ay += dy * w
            }
            // Normalize so combined magnitude is reasonable regardless of
            // where in the field we are.
            let amag = sqrt(ax * ax + ay * ay)
            if amag > 0 {
                ax /= amag
                ay /= amag
            }

            // Curl noise — same scale as the other panes for visual consistency.
            let (cx, cy) = FlowNoise.curl(x: x * 2.2, y: y * 2.2, t: t * 0.5)

            // 30% attractor, 70% curl — graph implied, not stamped on.
            return (ax * 0.3 + cx * 0.7, ay * 0.3 + cy * 0.7)
        },
        // Respawn anywhere — particles will drift toward a hub regardless.
        respawn: { CGPoint(x: Double.random(in: 0...1), y: Double.random(in: 0...1)) },
        lineWidth: 0.8
    )
}
