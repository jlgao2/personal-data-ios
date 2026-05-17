import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var calStore = CalendarStore.shared
    @State private var selectedTab: Tab = .interventions
    @State private var showTransportSettings = false
    @State private var showLogSession = false
    @State private var showWorkoutSession = false
    /// User-controlled feature gates (see TransportSettingsView).
    @AppStorage("med_alerts_enabled") private var medAlertsEnabled: Bool = false

    enum Tab: String, Hashable {
        case interventions, plan, profile, social

        /// Map to the router's mirrored enum. Kept here so the router file
        /// doesn't have to import or reach into `ContentView`.
        var thematic: ThematicBackground.Tab {
            switch self {
            case .interventions: return .interventions
            case .plan:          return .plan
            case .social:        return .social
            case .profile:       return .profile
            }
        }
    }

    /// Bottom padding added to every tab's scroll content so the last item
    /// clears the floating tab bar (which sits ~~58pt tall + 8pt bottom inset).
    private let tabBarClearance: CGFloat = 76

    var body: some View {
        // Manual tab switching via ZStack + conditional content. Replaces
        // the previous TabView wiring because hiding the system tab bar
        // (via .toolbar(.hidden, for: .tabBar) or UITabBar appearance
        // override) causes iOS to enable horizontal swipe-between-tabs
        // as an alternative navigation gesture — there's no SwiftUI
        // modifier to disable that swipe while keeping the tab bar
        // hidden. With manual switching, only the CustomTabBar buttons
        // can change `selectedTab`; no horizontal swipe is bound to
        // anything, so the "plan tab moves sideways as a piece" bug
        // disappears.
        ZStack {
            switch selectedTab {
            case .interventions: interventionsTab
            case .plan:          planTab
            case .social:        socialTab
            case .profile:       profileTab
            }
        }
        .preferredColorScheme(.dark)
        .tint(.cyan)
        .task { if store.bundle == nil { await store.bootstrap() } }
        .overlay(alignment: .bottom) {
            CustomTabBar(selected: $selectedTab)
        }
        .overlay(alignment: .bottom) {
            if let msg = store.lastUploadResult {
                Text(msg)
                    .font(.caption2.monospaced())
                    .padding(8)
                    .background(Color.cyan.opacity(0.15))
                    .foregroundStyle(.cyan)
                    .cornerRadius(4)
                    .padding(.bottom, 90)   // above the floating tab bar
                    .transition(.opacity)
                    .task(id: msg) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { store.lastUploadResult = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.lastUploadResult)
        .overlay(alignment: .center) {
            AchievementUnlockToast(pending: $store.pendingAchievements)
        }
        .sheet(isPresented: $showTransportSettings) {
            TransportSettingsView()
        }
        .sheet(isPresented: $showLogSession) {
            LogSessionView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showWorkoutSession) {
            if let bundle = store.bundle, let adapted = bundle.adapted_session {
                let dayKey = adapted.program_day ?? ""
                WorkoutSessionView(
                    dayKey: dayKey,
                    prescribed: bundle.profile?.daily_protocol?[dayKey],
                    trafficLight: adapted.traffic_light,
                    intensityPct: Int(((adapted.intensity_modifier ?? 1.0) * 100).rounded())
                )
                .environmentObject(store)
            }
        }
    }

    // MARK: - Interventions (today)

    @ViewBuilder
    private var interventionsTab: some View {
        // No NavigationStack — nothing in this pane pushes a NavigationLink,
        // and NavigationStack's UINavigationController brings an interactive
        // pop-gesture recognizer that can grab horizontal pans on root and
        // make the whole pane drift sideways as one block.
        ZStack {
            ThematicBackground(tab: .interventions).ignoresSafeArea()
            // NowFocusView owns its OWN vertical wheel scroll (snap +
            // scroll-transition). It must NOT be nested inside another
            // ScrollView or the two vertical scrolls fight and the snap
            // breaks — so loading / onboarding are siblings here, and
            // the wheel is the scroll surface (pull-to-refresh lives on
            // it via onRefresh).
            Group {
                if store.loading && store.bundle == nil {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let bundle = store.bundle {
                    NowFocusView(
                        bundle: bundle,
                        onStartWorkout: { showWorkoutSession = true },
                        onRefresh: {
                            await store.bootstrap()
                            await store.uploadTodaySamples()
                        }
                    )
                } else if iCloudPaths.isAvailable {
                    ConfigOnboardingView()
                }
            }
            if let err = store.lastError {
                VStack { Spacer(); errorBanner(err).padding(.bottom, tabBarClearance) }
            }
        }
        .overlay(alignment: .topTrailing) {
            TransportStatusPill()
                .padding(.top, 8)
                .padding(.trailing, 16)
        }
    }

    // MARK: - Plan & Vision

    @ViewBuilder
    private var planTab: some View {
        ZStack {
            ThematicBackground(tab: .plan).ignoresSafeArea()
            // Force vertical-only ScrollView axis; SwiftUI's default is
            // .vertical but being explicit guards against accidental
            // horizontal-axis enablement from nested modifiers.
            ScrollView(.vertical) {
                // Each child gets `.frame(maxWidth: .infinity)` so that if
                // any one of them emits content with an intrinsic width
                // larger than the viewport (a Chart, a fixed-width row, a
                // GeometryReader that doesn't clamp), that overflow stays
                // contained inside that child rather than propagating up
                // through the VStack to the ScrollView and making the
                // whole tab scroll sideways.
                VStack(alignment: .leading, spacing: 28) {
                    if let bundle = store.bundle {
                        if let p = bundle.profile {
                            PlanTabView(
                                profile: p,
                                vitals: bundle.vitals,
                                workouts: bundle.workouts,
                                actionLoop: bundle.action_loop,
                                live: store.liveValues
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        WeeklyRecapView(vitals: bundle.vitals, workouts: bundle.workouts)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let supps = bundle.profile?.supplement_stack, !supps.isEmpty {
                            StackDetailView(items: supps)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let corr = bundle.correlations {
                            if let findings = corr.correlations, !findings.isEmpty {
                                CorrelationsView(findings: findings)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let dow = corr.day_of_week, !dow.isEmpty {
                                DOWHeatmapView(stats: dow)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        VitalsView(vitals: bundle.vitals, live: store.liveValues)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !bundle.workouts.isEmpty {
                            WorkoutsView(workouts: bundle.workouts)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .padding(.top, 32)
                .padding(.bottom, tabBarClearance)
            }
            // Defense-in-depth: clipped on the ScrollView so even if a
            // child still produces an out-of-bounds box, it's visually
            // truncated rather than expanding the scrollable area.
            .clipped()
            // Backdrop lives in the per-tab ZStack above.
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbar(.hidden, for: .tabBar)
        }
    }

    // MARK: - Social

    @ViewBuilder
    private var socialTab: some View {
        ZStack {
            ThematicBackground(tab: .social).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let s = store.bundle?.social {
                        SocialView(summary: s)
                    } else {
                        Text("No social data — run refresh.sh with the social-media-graph repo present.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding()
                .padding(.top, 32)
                .padding(.bottom, tabBarClearance)
            }
            // Backdrop lives in the per-tab ZStack above.
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbar(.hidden, for: .tabBar)
        }
    }

    // MARK: - Profile

    @ViewBuilder
    private var profileTab: some View {
        ZStack {
            ThematicBackground(tab: .profile).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let bundle = store.bundle {
                        StreakChip()
                        AchievementGrid()
                        if let p = bundle.profile {
                            HealthProfileView(profile: p)
                        }
                        if medAlertsEnabled,
                           let avoid = bundle.profile?.medications_to_avoid,
                           !avoid.isEmpty {
                            MedReferenceView(classes: avoid)
                        }
                        if let g = bundle.genomics {
                            GenomicsView(genomics: g)
                        }
                    }
                }
                .padding()
                .padding(.top, 32)
                .padding(.bottom, tabBarClearance)
            }
            // Backdrop is rendered behind the TabView via `ThematicBackground`.
            // Keep the ScrollView's own surface clear so it shows through.
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbar(.hidden, for: .tabBar)
            .overlay(alignment: .topTrailing) {
                Button { showTransportSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.06)))
                }
                .buttonStyle(LivePressStyle())
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
    }

    // MARK: - Shared

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(4)
    }
}
