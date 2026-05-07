import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var calStore = CalendarStore.shared
    @State private var selectedTab: Tab = .interventions
    @State private var showTransportSettings = false

    enum Tab: String, Hashable {
        case interventions, plan, profile, social
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            interventionsTab
                .tabItem { Label("Now", systemImage: "target") }
                .tag(Tab.interventions)

            planTab
                .tabItem { Label("Plan", systemImage: "scope") }
                .tag(Tab.plan)

            socialTab
                .tabItem { Label("Social", systemImage: "person.2") }
                .tag(Tab.social)

            profileTab
                .tabItem { Label("Profile", systemImage: "person.text.rectangle") }
                .tag(Tab.profile)
        }
        .preferredColorScheme(.dark)
        .tint(.cyan)
        .task { if store.bundle == nil { await store.bootstrap() } }
        .overlay(alignment: .bottom) {
            if let msg = store.lastUploadResult {
                Text(msg)
                    .font(.caption2.monospaced())
                    .padding(8)
                    .background(Color.cyan.opacity(0.15))
                    .foregroundStyle(.cyan)
                    .cornerRadius(4)
                    .padding(.bottom, 80)
                    .transition(.opacity)
                    .task(id: msg) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { store.lastUploadResult = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.lastUploadResult)
        .sheet(isPresented: $showTransportSettings) {
            TransportSettingsView()
        }
    }

    // MARK: - Interventions (today)

    @ViewBuilder
    private var interventionsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.loading { ProgressView("Loading…").frame(maxWidth: .infinity, alignment: .center) }
                    if let err = store.lastError { errorBanner(err) }
                    if let bundle = store.bundle {
                        TimelineView(bundle: bundle, calStore: calStore)
                        if let adapted = bundle.adapted_session {
                            let dayKey = adapted.program_day ?? ""
                            let prescribed = bundle.profile?.daily_protocol?[dayKey]
                            AdaptedSessionView(adapted: adapted, prescribedSession: prescribed)
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
                .padding(.top, 32)   // breathing room under the dynamic island / status pill
            }
            .background { AnimatedAuraBackground() }
            .toolbar(.hidden, for: .navigationBar)
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
                        VitalsView(vitals: bundle.vitals, live: store.liveValues)
                        if !bundle.workouts.isEmpty {
                            WorkoutsView(workouts: bundle.workouts)
                        }
                    }
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
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
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Social")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
        }
    }

    // MARK: - Profile

    @ViewBuilder
    private var profileTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let bundle = store.bundle {
                        if let p = bundle.profile {
                            HealthProfileView(profile: p)
                        }
                        // Reference list of drug classes to avoid (separate
                        // from Interventions which surfaces firing alerts only)
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
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTransportSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
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
