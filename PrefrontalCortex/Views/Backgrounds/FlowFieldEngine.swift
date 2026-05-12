import SwiftUI
import UIKit

/// Shared particle/flow-field engine for the four thematic backdrops.
///
/// Each backdrop builds a `FlowFieldConfig` whose `flowAt(x:y:t:)` returns a
/// 2D vector at a normalized position + wall-clock time. The engine
/// integrates ~500 particles per pane, keeping a short trail of recent
/// positions per particle for the dense filament look (Refik Anadol-style).
/// `Canvas` + `TimelineView` at 30 FPS — no Metal needed.
///
/// Storage is a class held by `FlowFieldCanvas`'s `@StateObject` so it
/// survives body recomputes without reallocating. Velocity lerps toward the
/// field vector rather than snapping (streams feel "pulled"), and particles
/// carry a palette seed so co-spawned ones don't all blend identically.

// MARK: - Particle

/// A single particle. Reference type because the engine mutates ~500 of these
/// per frame; value semantics would force full-array copy on every tick.
final class Particle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var age: Double
    var lifespan: Double
    var paletteSeed: Double  // 0..1 offset along the palette per-particle

    /// Ring buffer of the last `trailCapacity` positions, flat as alternating
    /// x,y entries. `trailHead` is the next-write slot.
    var trail: [Double]
    var trailHead: Int
    var trailFilled: Int  // valid entries; caps at trailCapacity
    let trailCapacity: Int

    init(x: Double, y: Double, lifespan: Double, paletteSeed: Double, trailCapacity: Int) {
        self.x = x
        self.y = y
        self.vx = 0
        self.vy = 0
        self.age = 0
        self.lifespan = lifespan
        self.paletteSeed = paletteSeed
        self.trail = [Double](repeating: 0, count: trailCapacity * 2)
        self.trailHead = 0
        self.trailFilled = 0
        self.trailCapacity = trailCapacity
    }

    /// Write the current position into the trail ring.
    func pushTrail() {
        trail[trailHead * 2] = x
        trail[trailHead * 2 + 1] = y
        trailHead = (trailHead + 1) % trailCapacity
        if trailFilled < trailCapacity { trailFilled += 1 }
    }

    /// Reset state for respawn at the given point.
    func respawn(at point: CGPoint, lifespan: Double, paletteSeed: Double) {
        x = Double(point.x)
        y = Double(point.y)
        vx = 0
        vy = 0
        age = 0
        self.lifespan = lifespan
        self.paletteSeed = paletteSeed
        trailHead = 0
        trailFilled = 0
    }
}

// MARK: - Config

/// Per-pane parameters. `flowAt` is the personality knob — the curl-noise /
/// attractor field whose shape gives each backdrop its character.
struct FlowFieldConfig {
    let particleCount: Int
    let trailCapacity: Int
    let minLifespan: Double
    let maxLifespan: Double
    /// Per-frame lerp factor velocity → field vector. 0.08–0.18 is the
    /// usable range for 30 FPS; smaller is lazier, larger is jittery.
    let velocityLerp: Double
    /// Stream speed: multiplied into the field vector before integration.
    let speed: Double
    let palette: [Color]
    let flowAt: (Double, Double, Double) -> (Double, Double)
    /// Where new/respawned particles enter (unit-square coords). Called
    /// both at initial seeding and every respawn.
    let respawn: () -> CGPoint
    /// Trail stroke width. Roots wants chunkier filaments; River thinner.
    let lineWidth: Double

    /// Sample the palette at `u` (0..1) by linearly interpolating between
    /// the two adjacent stops.
    func color(at u: Double) -> Color {
        guard !palette.isEmpty else { return .white }
        if palette.count == 1 { return palette[0] }
        let clamped = max(0, min(1, u))
        let scaled = clamped * Double(palette.count - 1)
        let lo = Int(floor(scaled))
        let hi = min(lo + 1, palette.count - 1)
        return blend(palette[lo], palette[hi], t: scaled - Double(lo))
    }

    private func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        // SwiftUI `Color` doesn't expose components; resolve via UIColor
        // and interpolate in RGB. Cost is fine — once per particle per frame.
        let ua = UIColor(a), ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let tt = CGFloat(t)
        return Color(
            red:   Double(ar + (br - ar) * tt),
            green: Double(ag + (bg - ag) * tt),
            blue:  Double(ab + (bb - ab) * tt),
            opacity: Double(aa + (ba - aa) * tt)
        )
    }
}

// MARK: - Engine state

/// Owns the live particle array. Stored as `@StateObject` so it persists
/// across body recomputes. Deliberately no `@Published`: the canvas reads
/// `particles` inside its draw closure each frame, so publishing every
/// tick would just spam SwiftUI's update graph.
final class FlowFieldEngine: ObservableObject {
    let config: FlowFieldConfig
    private(set) var particles: [Particle]
    /// Last wall-clock tick (seconds since reference); used for dt.
    private var lastTickAt: TimeInterval = 0

    init(config: FlowFieldConfig) {
        self.config = config
        self.particles = []
        self.particles.reserveCapacity(config.particleCount)
        for _ in 0..<config.particleCount {
            let p = config.respawn()
            let lifespan = Double.random(in: config.minLifespan...config.maxLifespan)
            let particle = Particle(
                x: Double(p.x), y: Double(p.y),
                lifespan: lifespan,
                paletteSeed: Double.random(in: 0...1),
                trailCapacity: config.trailCapacity
            )
            // Stagger initial age so lifespans don't all line up.
            particle.age = Double.random(in: 0...lifespan)
            particles.append(particle)
        }
    }

    /// Advance simulation to wall-clock `now`. Idempotent within ~1ms: if
    /// called twice in the same frame (layout passes can do this), the
    /// second call returns without re-integrating.
    func advance(to now: TimeInterval) {
        let dt: Double
        if lastTickAt == 0 {
            dt = 1.0 / 30.0
        } else {
            let raw = now - lastTickAt
            if raw < 0.001 { return }
            dt = min(max(raw, 0.005), 0.1)
        }
        lastTickAt = now
        let lerp = config.velocityLerp
        let speed = config.speed
        for p in particles {
            let (fx, fy) = config.flowAt(p.x, p.y, now)
            p.vx += (fx * speed - p.vx) * lerp
            p.vy += (fy * speed - p.vy) * lerp
            p.x += p.vx
            p.y += p.vy
            p.age += dt
            p.pushTrail()
            if p.age > p.lifespan || p.x < -0.05 || p.x > 1.05 || p.y < -0.05 || p.y > 1.05 {
                let np = config.respawn()
                let life = Double.random(in: config.minLifespan...config.maxLifespan)
                p.respawn(at: np, lifespan: life, paletteSeed: Double.random(in: 0...1))
            }
        }
    }
}

// MARK: - Canvas view

/// Owns an engine and renders it. Drop into a per-pane `ZStack`.
struct FlowFieldCanvas: View {
    @StateObject private var engine: FlowFieldEngine

    init(config: FlowFieldConfig) {
        _engine = StateObject(wrappedValue: FlowFieldEngine(config: config))
    }

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            // Advance + render inside the Canvas closure — runs once per
            // frame for the actual draw. Doing tick in the TimelineView
            // view-builder doubles up on layout passes for some tabs.
            Canvas { ctx, size in
                engine.advance(to: now)
                draw(ctx: ctx, size: size)
            }
            .blendMode(.screen)
            .ignoresSafeArea()
        }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let lineWidth = engine.config.lineWidth
        for p in engine.particles {
            guard p.trailFilled > 1 else { continue }
            // Walk trail oldest → newest. When the ring is full, `trailHead`
            // is the oldest slot (next-write also = oldest); pre-fill, it's 0.
            let cap = p.trailCapacity
            let filled = p.trailFilled
            let startSlot = filled < cap ? 0 : p.trailHead

            // Color: blend along palette by age + per-particle seed.
            let u = (p.age / p.lifespan + p.paletteSeed).truncatingRemainder(dividingBy: 1.0)
            let baseColor = engine.config.color(at: u)
            // Envelope: 0 at birth, 1 mid-life, 0 at death — no pop.
            let lifeFrac = max(0, min(1, p.age / p.lifespan))
            let envelope = sin(lifeFrac * .pi)

            for i in 0..<(filled - 1) {
                let aSlot = (startSlot + i) % cap
                let bSlot = (startSlot + i + 1) % cap
                let ax = p.trail[aSlot * 2] * size.width
                let ay = p.trail[aSlot * 2 + 1] * size.height
                let bx = p.trail[bSlot * 2] * size.width
                let by = p.trail[bSlot * 2 + 1] * size.height
                // Alpha rises along the trail (tail dim, head bright).
                let segFrac = Double(i + 1) / Double(filled)
                let alpha = segFrac * segFrac * 0.55 * envelope
                var seg = Path()
                seg.move(to: CGPoint(x: ax, y: ay))
                seg.addLine(to: CGPoint(x: bx, y: by))
                ctx.stroke(
                    seg,
                    with: .color(baseColor.opacity(alpha)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Noise

/// 2D Perlin gradient noise + curl. Curl is the finite-difference of a
/// scalar potential, so the resulting field is divergence-free — streams
/// don't collapse to a point or fan out from one.
enum FlowNoise {
    /// Classic Perlin permutation, doubled so we never `% 256` on access.
    static let perm: [Int] = {
        var p = Array(0..<256)
        // Fixed seed so backdrops look identical across launches.
        var rng = LCG(seed: 0xC0FFEE)
        // Fisher-Yates shuffle.
        for i in stride(from: 255, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            p.swapAt(i, j)
        }
        return p + p
    }()

    /// 2D gradient vectors (8 directions). Indexed by perm table lookup.
    private static let grads: [(Double, Double)] = [
        ( 1,  0), (-1,  0), ( 0,  1), ( 0, -1),
        ( 0.7071,  0.7071), (-0.7071, 0.7071),
        ( 0.7071, -0.7071), (-0.7071, -0.7071),
    ]

    /// Quintic fade (Perlin's improved). Smoother than cubic — important
    /// for streams because cubic shows lattice-aligned banding.
    @inline(__always) private static func fade(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// 2D gradient (Perlin) noise. Output ~[-1, 1].
    static func perlin2(_ x: Double, _ y: Double) -> Double {
        let xi = Int(floor(x)) & 255
        let yi = Int(floor(y)) & 255
        let xf = x - floor(x)
        let yf = y - floor(y)
        let u = fade(xf)
        let v = fade(yf)
        let aa = perm[perm[xi] + yi]
        let ab = perm[perm[xi] + yi + 1]
        let ba = perm[perm[xi + 1] + yi]
        let bb = perm[perm[xi + 1] + yi + 1]
        let n00 = dot(grads[aa & 7], xf,     yf)
        let n10 = dot(grads[ba & 7], xf - 1, yf)
        let n01 = dot(grads[ab & 7], xf,     yf - 1)
        let n11 = dot(grads[bb & 7], xf - 1, yf - 1)
        let nx0 = n00 + u * (n10 - n00)
        let nx1 = n01 + u * (n11 - n01)
        return nx0 + v * (nx1 - nx0)
    }

    @inline(__always) private static func dot(_ g: (Double, Double), _ x: Double, _ y: Double) -> Double {
        g.0 * x + g.1 * y
    }

    /// Curl of scalar potential phi(x,y) = (∂phi/∂y, -∂phi/∂x). We time-
    /// shift `y` to fake 3D motion cheaply, and combine two offset noise
    /// fields so the curl doesn't collapse into a single rotation.
    static func curl(x: Double, y: Double, t: Double) -> (Double, Double) {
        let eps = 0.01
        let ty = t * 0.15
        let phi = perlin2(x, y + ty) + 0.5 * perlin2(x + 31.4, y + 17.2 + ty)
        let pyP = perlin2(x, y + eps + ty) + 0.5 * perlin2(x + 31.4, y + 17.2 + eps + ty)
        let pxP = perlin2(x + eps, y + ty) + 0.5 * perlin2(x + 31.4 + eps, y + 17.2 + ty)
        return ((pyP - phi) / eps, -(pxP - phi) / eps)
    }
}

/// Tiny LCG used only at static init of the noise permutation table.
private struct LCG {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
