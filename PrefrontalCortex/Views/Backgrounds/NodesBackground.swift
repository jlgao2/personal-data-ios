import SwiftUI

/// Backdrop for the `.social` tab: a sparse graph of ~50 nodes joined by edges
/// to nearest-K neighbors, with small light pulses traveling along each edge
/// on independent phase offsets. Layout is precomputed once from a seeded RNG
/// so the graph is stable across launches and SwiftUI body recomputes; per
/// frame we only interpolate edge positions and draw circles.
///
/// Render budget: 50 nodes + ~150 edges drawn into a single `Canvas` at 30 FPS.
/// Conservative on purpose — the brief explicitly caps this.
struct NodesBackground: View {
    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // Deep base. Matches the indigo-on-black palette the other
                // backdrops are tuned to.
                Color.black

                // Soft indigo wash so the graph reads against the black
                // ground without competing with foreground text.
                RadialGradient(
                    colors: [
                        Color.indigo.opacity(0.18),
                        Color.indigo.opacity(0.04),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.45),
                    startRadius: 80,
                    endRadius: 560
                )

                NodesCanvas(now: t)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Canvas

private struct NodesCanvas: View {
    let now: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            let nodes = Graph.shared.nodes
            let edges = Graph.shared.edges

            // Edges first so node disks render on top.
            for edge in edges {
                let a = nodes[edge.a]
                let b = nodes[edge.b]
                let pa = CGPoint(x: a.x * size.width, y: a.y * size.height)
                let pb = CGPoint(x: b.x * size.width, y: b.y * size.height)

                var line = Path()
                line.move(to: pa)
                line.addLine(to: pb)
                ctx.stroke(
                    line,
                    with: .color(.cyan.opacity(0.08)),
                    lineWidth: 0.5
                )

                // Light pulse traveling along the edge. Each edge has its
                // own phase + period so the field never strobes in unison.
                let u = phaseFraction(now: now, phase: edge.phase, period: edge.period)
                let px = pa.x + (pb.x - pa.x) * u
                let py = pa.y + (pb.y - pa.y) * u
                let pulseRadius = 1.4
                let pulseRect = CGRect(
                    x: px - pulseRadius, y: py - pulseRadius,
                    width: pulseRadius * 2, height: pulseRadius * 2
                )
                // Fade pulse in/out near the ends so it doesn't pop.
                let envelope = sin(u * .pi)
                ctx.fill(
                    Path(ellipseIn: pulseRect),
                    with: .color(.cyan.opacity(0.55 * envelope))
                )
                // Soft halo
                let haloRect = pulseRect.insetBy(dx: -pulseRadius * 1.8, dy: -pulseRadius * 1.8)
                ctx.fill(
                    Path(ellipseIn: haloRect),
                    with: .color(.cyan.opacity(0.18 * envelope))
                )
            }

            // Nodes — small dim disks with a quiet brightness pulse.
            for node in nodes {
                let center = CGPoint(x: node.x * size.width, y: node.y * size.height)
                let pulse = (sin(now * 2 * .pi / node.period + node.phase) + 1) / 2
                let alpha = node.baseAlpha * (0.6 + 0.4 * pulse)
                let r = node.radius
                let rect = CGRect(
                    x: center.x - r, y: center.y - r,
                    width: r * 2, height: r * 2
                )
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
        .blendMode(.screen)
    }

    /// 0..1 progress along the edge, looping with `period`.
    private func phaseFraction(now: TimeInterval, phase: Double, period: Double) -> Double {
        let raw = (now / period) + phase
        return raw - floor(raw)
    }
}

// MARK: - Graph (precomputed once)

private struct GraphNode {
    let x: Double          // 0..1 in viewport
    let y: Double
    let radius: Double     // points
    let baseAlpha: Double
    let phase: Double      // radians
    let period: Double     // seconds
}

private struct GraphEdge {
    let a: Int             // index into nodes
    let b: Int
    let phase: Double      // 0..1 starting offset along the edge
    let period: Double     // seconds for a pulse to traverse end-to-end
}

/// The graph is generated once from a fixed seed so it stays put across
/// launches. ~50 nodes; each node connects to its nearest 3 neighbors
/// (de-duplicated, so the edge count lands around 75–90).
private enum Graph {
    static let shared: (nodes: [GraphNode], edges: [GraphEdge]) = build()

    private static let nodeCount = 50
    private static let nearestK = 3

    private static func build() -> (nodes: [GraphNode], edges: [GraphEdge]) {
        var rng = SeededRNG(seed: 42)

        var nodes: [GraphNode] = []
        nodes.reserveCapacity(nodeCount)
        for _ in 0..<nodeCount {
            nodes.append(
                GraphNode(
                    // Inset slightly so nodes don't hug the screen edge.
                    x: 0.04 + 0.92 * rng.next01(),
                    y: 0.06 + 0.88 * rng.next01(),
                    radius: rng.next(in: 1.2...2.4),
                    baseAlpha: rng.next(in: 0.35...0.75),
                    phase: rng.next(in: 0...(2 * .pi)),
                    period: rng.next(in: 5...12)
                )
            )
        }

        // Build edges: each node -> nearest K others. Dedupe (a,b) pairs.
        var edgeSet = Set<EdgeKey>()
        var edges: [GraphEdge] = []
        for i in 0..<nodes.count {
            let me = nodes[i]
            // Score every other node by squared distance, take K smallest.
            var distances: [(Int, Double)] = []
            distances.reserveCapacity(nodes.count - 1)
            for j in 0..<nodes.count where j != i {
                let dx = me.x - nodes[j].x
                let dy = me.y - nodes[j].y
                distances.append((j, dx * dx + dy * dy))
            }
            distances.sort { $0.1 < $1.1 }
            for k in 0..<min(nearestK, distances.count) {
                let j = distances[k].0
                let key = EdgeKey(a: min(i, j), b: max(i, j))
                if edgeSet.insert(key).inserted {
                    edges.append(
                        GraphEdge(
                            a: key.a,
                            b: key.b,
                            phase: rng.next01(),
                            period: rng.next(in: 4.5...9.0)
                        )
                    )
                }
            }
        }
        return (nodes, edges)
    }

    private struct EdgeKey: Hashable {
        let a: Int
        let b: Int
    }
}

// MARK: - RNG

/// Linear-congruential RNG. Same shape as the one in `AnimatedAuraBackground`
/// but kept local so the two backdrops can evolve independently. Deterministic
/// across launches given a fixed seed.
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
