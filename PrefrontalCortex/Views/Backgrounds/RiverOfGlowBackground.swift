import SwiftUI

/// Backdrop for the `.plan` tab.
///
/// Personality: river of glow — strong horizontal flow with a gentle
/// vertical wiggle, amber + cyan stops layered so the streams read like
/// laminar light. Particles enter from the left edge and advect right.
///
/// Palette: cyan → muted blue → amber → soft yellow. The amber dominates
/// midstream so the river has a "warm current" look, not a cold one.
struct RiverOfGlowBackground: View {
    var body: some View {
        ZStack {
            Color.black

            // Cyan-warm wash, off-center to the left so the river feels like
            // it sources from somewhere offscreen.
            RadialGradient(
                colors: [
                    Color(hue: 0.55, saturation: 0.55, brightness: 0.22).opacity(0.5),
                    Color(hue: 0.08, saturation: 0.3, brightness: 0.15).opacity(0.18),
                    .clear,
                ],
                center: UnitPoint(x: 0.25, y: 0.5),
                startRadius: 60,
                endRadius: 600
            )

            FlowFieldCanvas(config: Self.config)
        }
        .ignoresSafeArea()
    }

    // Palette is hoisted to its own typed constant so Swift's type-checker
    // doesn't have to infer through the mixed Color expressions
    // (Color.opacity, Color(hue:saturation:brightness:), shorthand) inside
    // the larger FlowFieldConfig initialiser. Without this hoist the
    // inline literal causes "compiler unable to type-check in reasonable
    // time" build failures.
    private static let palette: [Color] = [
        .cyan,
        Color(hue: 0.55, saturation: 0.7, brightness: 0.9),
        Color.orange.opacity(0.6),
        Color.yellow.opacity(0.4),
    ]

    private static let config = FlowFieldConfig(
        particleCount: 200,    // dialed down — less powerful
        trailCapacity: 26,     // longest trails (still the streak look at lower density)
        minLifespan: 7.0,
        maxLifespan: 12.0,
        velocityLerp: 0.06,    // smoother, more painterly current
        speed: 0.0016,         // ~40% of prior speed — still a river, slow water
        palette: palette,
        // Strong x-direction flow with a gentle vertical wiggle. Tilted
        // slightly so the river isn't perfectly horizontal (more painterly
        // when it angles 5–10° down across the frame).
        flowAt: { x, y, t in
            let n = FlowNoise.perlin2(x * 1.6, y / 3.0 + t * 0.05)
            // Push primarily right; vertical wiggle is 1/4 the amplitude.
            let dx = cos(n) * 0.95 + 0.15  // bias so it never reverses
            let dy = sin(n) * 0.25
            return (dx, dy)
        },
        // Respawn from the left edge (and a small fringe above/below) so
        // the river always has a source. Random y so the streams stack.
        respawn: { CGPoint(x: Double.random(in: -0.04...0.02), y: Double.random(in: -0.05...1.05)) },
        lineWidth: 0.7
    )
}
