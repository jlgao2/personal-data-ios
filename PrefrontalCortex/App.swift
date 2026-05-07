import SwiftUI

@main
struct PrefrontalCortexApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    await store.bootstrap()
                }
        }
    }
}
