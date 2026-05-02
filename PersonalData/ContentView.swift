import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if store.loading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    if let err = store.lastError {
                        Text(err)
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                    if let bundle = store.bundle {
                        TodayHeaderView(bundle: bundle)
                        ActionLoopView(cards: bundle.action_loop, live: store.liveValues)
                        VitalsView(vitals: bundle.vitals, live: store.liveValues)
                        if let items = bundle.profile?.prep_checklist_template, !items.isEmpty {
                            PrepChecklistView(items: items)
                        }
                        if let stack = bundle.profile?.supplement_stack, !stack.isEmpty {
                            StackView(items: stack)
                        }
                        if !bundle.workouts.isEmpty {
                            WorkoutsView(workouts: bundle.workouts)
                        }
                        if let g = bundle.genomics {
                            GenomicsView(genomics: g)
                        }
                    }
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Personal Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.uploadTodaySamples() }
                    } label: {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                }
            }
            .refreshable {
                await store.bootstrap()
            }
            .overlay(alignment: .bottom) {
                if let msg = store.lastUploadResult {
                    Text(msg)
                        .font(.caption2.monospaced())
                        .padding(8)
                        .background(Color.cyan.opacity(0.15))
                        .foregroundStyle(.cyan)
                        .cornerRadius(4)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}
