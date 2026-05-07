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
                        Task { await store.refreshOnForeground() }
                    }
                }
        }
    }
}
