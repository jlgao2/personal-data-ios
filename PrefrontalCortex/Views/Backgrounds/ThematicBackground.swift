import SwiftUI

/// Router for per-tab animated backgrounds. `ContentView` renders this once
/// behind the `TabView`; we pick the right backdrop based on the currently
/// selected tab. Each backdrop is a curl-noise / Perlin-driven flow field
/// (see `FlowFieldEngine.swift`) tuned to its pane's personality:
///
///  * `.interventions` → `RhizomaticBackground` (lateral branching streams)
///  * `.plan`          → `RiverOfGlowBackground` (laminar amber+cyan)
///  * `.social`        → `NodesBackground` (network attractor field)
///  * `.profile`       → `RootsBackground` (vertical-downward earth tones)
///
/// Per-tab transitions are handled by `ContentView`'s `TabView` — no
/// `.animation(...)` here. The per-tab `ZStack` pattern means each pane
/// owns its own backdrop instance, so the engine state (particle
/// positions/trails) survives tab switches.
struct ThematicBackground: View {
    /// Mirrors the case names of `ContentView.Tab` so this router does not
    /// have to depend on `ContentView`'s nested type from another scope.
    /// Keep these case names in sync with `ContentView.Tab`.
    enum Tab: String, Hashable {
        case interventions, plan, social, profile
    }

    let tab: Tab

    var body: some View {
        switch tab {
        case .interventions: RhizomaticBackground()
        case .plan:          RiverOfGlowBackground()
        case .social:        NodesBackground()
        case .profile:       RootsBackground()
        }
    }
}
