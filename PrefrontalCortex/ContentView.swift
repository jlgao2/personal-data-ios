import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var calStore = CalendarStore.shared
    @State private var selectedTab: Tab = .interventions
    @State private var showTransportSettings = false
    @State private var showLogSession = false
    @State private var showWorkoutSession = false

    enum Tab: String, Hashable {
        case interventions, plan, profile, social
    }

    /// Bottom padding added to every tab's scroll content so the last item
    /// clears the floating tab bar (which sits ~~58pt tall + 8pt bottom inset).
    private let tabBarClearance: CGFloat = 76

    var body: some View {
        TabView(selection: $selectedTab) {
            interventionsTab
                .tag(Tab.interventions)
            planTab
                .tag(Tab.plan)
            socialTab
                .tag(Tab.social)
            profileTab
                .tag(Tab.profile)
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.loading {
                        ProgressView("Loading…").frame(maxWidth: .infinity, alignment: .center)
                    }
                    if let err = store.lastError { errorBanner(err) }
                    if let bundle = store.bundle {
                        TimelineView(bundle: bundle, calStore: calStore)
                        DailyLockChip()
                        if let supps = bundle.profile?.supplement_stack, !supps.isEmpty {
                            StackView(items: supps)
                        }
                        MindfulEatingTodayView()
                        if let adapted = bundle.adapted_session {
                            let dayKey = adapted.program_day ?? ""
                            let prescribed = bundle.profile?.daily_protocol?[dayKey]
                            AdaptedSessionView(
                                adapted: adapted,
                                prescribedSession: prescribed,
                                onStart: { showWorkoutSession = true }
                            )
                        }
                        if let abst = bundle.profile?.abstinences, !abst.isEmpty {
                            AbstinenceBarView(abstinences: abst)
                        }
                        MedAlertsView(
                            alerts: bundle.med_alerts ?? [],
                            avoidClasses: bundle.profile?.medications_to_avoid ?? []
                        )
                        if !calStore.authorized {
                            UpcomingEventsView(
                                bundleEvents: bundle.calendar ?? [],
                                store: calStore
                            )
                        }
                    }
                }
                .padding()
                .padding(.top, 32)
                .padding(.bottom, tabBarClearance)
            }
            .background { AnimatedAuraBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .refreshable {
                await store.bootstrap()
                await store.uploadTodaySamples()
            }
            .overlay(alignment: .topTrailing) {
                TransportStatusPill(
                    bundleExportedAt: store.bundle?.exported_at,
                    lastError: store.lastTransportError,
                    presentSettings: $showTransportSettings
                )
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
    }

    // MARK: - Plan & Vision

    @ViewBuilder
    private var planTab: some View {
        NavigationStack {
            ScrollView {
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
                        }
                        WeeklyRecapView(vitals: bundle.vitals, workouts: bundle.workouts)
                        if let supps = bundle.profile?.supplement_stack, !supps.isEmpty {
                            StackDetailView(items: supps)
                        }
                        if let corr = bundle.correlations {
                            if let findings = corr.correlations, !findings.isEmpty {
                                CorrelationsView(findings: findings)
                            }
                            if let dow = corr.day_of_week, !dow.isEmpty {
                                DOWHeatmapView(stats: dow)
                            }
                        }
                        VitalsView(vitals: bundle.vitals, live: store.liveValues)
                        if !bundle.workouts.isEmpty {
                            WorkoutsView(workouts: bundle.workouts)
                        }
                    }
                }
                .padding()
                .padding(.top, 32)
                .padding(.bottom, tabBarClearance)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
        }
    }

    // MARK: - Social

    @ViewBuilder
    private var socialTab: some View {
        NavigationStack {
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
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
        }
    }

    // MARK: - Profile

    @ViewBuilder
    private var profileTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let bundle = store.bundle {
                        StreakChip()
                        AchievementGrid()
                        if let p = bundle.profile {
                            HealthProfileView(profile: p)
                        }
                        if let avoid = bundle.profile?.medications_to_avoid,
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
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
