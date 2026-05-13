import SwiftUI

@main
struct PrefrontalCortexApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    await store.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && store.bundle != nil {
                        // Broadcast the rollover so date-derived views
                        // (DailyLockChip, AdaptedSessionView, TimelineView)
                        // re-evaluate from `Date()` on foreground — covers
                        // the "app left open across midnight" case where
                        // .onAppear doesn't re-fire.
                        NotificationCenter.default.post(name: .dayDidRollOver, object: nil)
                        Task { await store.refreshOnForeground() }
                    }
                }
        }
    }
}
