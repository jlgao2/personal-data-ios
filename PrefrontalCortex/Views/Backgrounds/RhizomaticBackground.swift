import SwiftUI

/// Backdrop for the `.interventions` (Now) tab.
///
/// Personality: rhizomatic — branching, lateral spread, slow growth feel.
/// The flow field is curl noise *rotated 90°* with low speed so streams
/// drift sideways more than they advect down. A second slow noise term
/// gates the rotation so neighboring streams sometimes fork off in
/// different directions, giving the "branching" read.
///
/// Palette: cyan → teal → warm green. Lives in the same dark-indigo base
/// the other panes use but tinted slightly green so roots/plants are
/// implied.
struct RhizomaticBackground: View {
    var body: some View {
        ZStack {
            // Deep base. Slightly green-tinted so the palette doesn't fight
            // the ground.
            Color.black

            RadialGradient(
                colors: [
                    Color(hue: 0.42, saturation: 0.5, brightness: 0.18).opacity(0.55),
                    Color(hue: 0.55, saturation: 0.4, brightness: 0.12).opacity(0.25),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.55),
                startRadius: 60,
                endRadius: 580
            )

            FlowFieldCanvas(config: Self.config)
        }
        .ignoresSafeArea()
    }

    // Hoisted palette — see RiverOfGlowBackground for the rationale (Swift
    // type-checker times out on inline mixed Color expressions inside the
    // larger FlowFieldConfig initialiser).
    private static let palette: [Color] = [
        .cyan,
        .teal,
        Color(hue: 0.35, saturation: 0.6, brightness: 0.9),
        Color.green.opacity(0.7),
    ]

    private static let config = FlowFieldConfig(
        particleCount: 500,
        trailCapacity: 18,
        minLifespan: 6.0,
        maxLifespan: 11.0,
        velocityLerp: 0.10,
        speed: 0.0025,
        palette: palette,
        // Curl noise rotated 90° gives lateral spread (the "rhizomatic" feel).
        // A second low-frequency noise term reverses direction in places so
        // streams fork laterally rather than all flowing one way.
        flowAt: { x, y, t in
            let scale = 2.4
            let (cx, cy) = FlowNoise.curl(x: x * scale, y: y * scale, t: t * 0.6)
            // Rotate 90° — (cx, cy) → (-cy, cx)
            let rx = -cy
            let ry = cx
            // Branching gate: when this auxiliary noise crosses zero, flip
            // the lateral component. The transition is per-position, so
            // it shows up as forks rather than a global reversal.
            let gate = FlowNoise.perlin2(x * 1.6 + 11.0, y * 1.6 + 7.0 + t * 0.04)
            let branchSign: Double = gate > 0 ? 1.0 : -1.0
            // Bias horizontal slightly stronger than vertical for the
            // ground-cover read.
            return (rx * 1.1 * branchSign, ry * 0.7)
        },
        // Respawn anywhere — rhizomes spread from all directions.
        respawn: { CGPoint(x: Double.random(in: 0...1), y: Double.random(in: 0...1)) },
        lineWidth: 0.8
    )
}
