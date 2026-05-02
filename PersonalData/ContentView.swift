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
                        if let stack = bundle.profile?.supplement_stack, !stack.isEmpty {
                            StackView(items: stack)
                        }
                        if let items = bundle.profile?.prep_checklist_template, !items.isEmpty {
                            PrepChecklistView(items: items)
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
            .refreshable {
                await store.bootstrap()
            }
        }
    }
}
