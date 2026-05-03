import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab: Tab = .today

    enum Tab: String, Hashable {
        case today, trends, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            todayTab
                .tabItem { Label("Today", systemImage: "target") }
                .tag(Tab.today)

            trendsTab
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.trends)

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
            }
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todayTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.loading { ProgressView("Loading…").frame(maxWidth: .infinity, alignment: .center) }
                    if let err = store.lastError { errorBanner(err) }
                    if let bundle = store.bundle {
                        TodayHeaderView(bundle: bundle)
                        if let adapted = bundle.adapted_session {
                            let dayKey = adapted.program_day ?? ""
                            let prescribed = bundle.profile?.daily_protocol?[dayKey]
                            AdaptedSessionView(adapted: adapted, prescribedSession: prescribed)
                        }
                        ActionLoopView(cards: bundle.action_loop, live: store.liveValues)
                        if let stack = bundle.profile?.supplement_stack, !stack.isEmpty {
                            StackView(items: stack)
                        }
                        if let items = bundle.profile?.prep_checklist_template, !items.isEmpty {
                            PrepChecklistView(items: items)
                        }
                    }
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar { uploadToolbar }
            .refreshable { await store.bootstrap() }
        }
    }

    // MARK: - Trends

    @ViewBuilder
    private var trendsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let bundle = store.bundle {
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
            .navigationTitle("Trends")
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
                        MedAlertsView(
                            alerts: bundle.med_alerts ?? [],
                            avoidClasses: bundle.profile?.medications_to_avoid ?? []
                        )
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
        }
    }

    // MARK: - Shared

    private var uploadToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await store.uploadTodaySamples() }
            } label: {
                Image(systemName: "icloud.and.arrow.up")
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(4)
    }
}
