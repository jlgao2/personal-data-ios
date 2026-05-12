import SwiftUI

/// Backdrop for the `.profile` tab.
///
/// Personality: roots — vertical downward bias with horizontal branching.
/// Particles spawn near the top and fall, with curl noise modulating their
/// lateral position so the lines fork and rejoin like a root system.
///
/// Palette: deep amber, soft orange, muted indigo, brown — earth tones.
/// Slightly higher saturation than the other panes because the dark base
/// would otherwise eat the amber.
struct RootsBackground: View {
    var body: some View {
        ZStack {
            Color.black

            // Warm dark base — umber/amber tinted so the earth-tone palette
            // doesn't look orphaned over a cold indigo ground.
            RadialGradient(
                colors: [
                    Color(hue: 0.08, saturation: 0.55, brightness: 0.20).opacity(0.55),
                    Color(hue: 0.65, saturation: 0.45, brightness: 0.14).opacity(0.22),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.30),
                startRadius: 60,
                endRadius: 600
            )

            FlowFieldCanvas(config: Self.config)
        }
        .ignoresSafeArea()
    }

    // Hoisted palette — see RiverOfGlowBackground for the rationale.
    private static let palette: [Color] = [
        Color(hue: 0.08, saturation: 0.7, brightness: 0.6),
        Color.orange.opacity(0.5),
        Color(hue: 0.65, saturation: 0.4, brightness: 0.3),
        Color.brown.opacity(0.6),
    ]

    private static let config = FlowFieldConfig(
        particleCount: 500,
        trailCapacity: 20,
        minLifespan: 5.5,
        maxLifespan: 10.0,
        velocityLerp: 0.09,  // slower lerp — roots feel deliberate
        speed: 0.0028,
        palette: palette,
        // Vertical-downward bias. Curl provides the lateral wiggle/branch,
        // but the y-component is `|curl_y| + 0.5` so it never reverses
        // (roots don't grow up). The lateral component is curl_x scaled
        // down so streams meander instead of swerving wildly.
        flowAt: { x, y, t in
            let (cx, cy) = FlowNoise.curl(x: x * 2.0, y: y * 2.0, t: t * 0.4)
            let dx = cx * 0.45
            let dy = abs(cy) * 0.85 + 0.65  // always downward
            return (dx, dy)
        },
        // Respawn near the top with a thin band on the sides too — fewer
        // particles enter from the edges so the field thickens with depth.
        respawn: {
            let r = Double.random(in: 0...1)
            if r < 0.86 {
                return CGPoint(x: Double.random(in: -0.05...1.05), y: Double.random(in: -0.05...0.05))
            } else if r < 0.93 {
                return CGPoint(x: Double.random(in: -0.05...0.0), y: Double.random(in: 0...0.4))
            } else {
                return CGPoint(x: Double.random(in: 1.0...1.05), y: Double.random(in: 0...0.4))
            }
        },
        lineWidth: 0.95  // chunkier so the roots have weight
    )
}
