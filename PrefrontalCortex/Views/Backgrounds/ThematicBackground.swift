import SwiftUI

/// Router for per-tab animated backgrounds. `ContentView` renders this once
/// behind the `TabView`; we pick the right backdrop based on the currently
/// selected tab. The MVP only ships a distinct backdrop for `.social`
/// (`NodesBackground`); the other three tabs fall back to `AnimatedAuraBackground`
/// so nothing visually regresses while subsequent pane PRs land
/// (Rhizomatic / RiverOfGlow / Roots). See
/// `docs/superpowers/specs/2026-05-11-thematic-backgrounds-brief.md`.
struct ThematicBackground: View {
    /// Mirrors the case names of `ContentView.Tab` so this router does not
    /// have to depend on `ContentView`'s nested type from another scope.
    /// Keep these case names in sync with `ContentView.Tab`.
    enum Tab: String, Hashable {
        case interventions, plan, social, profile
    }

    let tab: Tab

    var body: some View {
        ZStack {
            switch tab {
            case .social:
                NodesBackground()
            case .interventions, .plan, .profile:
                // MVP fallback. Subsequent PRs replace each of these in turn
                // with RhizomaticBackground / RiverOfGlowBackground / RootsBackground.
                AnimatedAuraBackground()
            }
        }
        // Cross-fade between backdrops when the tab changes. Brief calls for
        // ~400ms; keep it on the container so the swap inside the ZStack
        // animates rather than hard-cutting.
        .animation(.easeInOut(duration: 0.4), value: tab)
    }
}
