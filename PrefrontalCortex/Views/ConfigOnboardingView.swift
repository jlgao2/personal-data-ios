import SwiftUI

/// Shown when iCloud is signed in but the Mac pipeline hasn't yet
/// written a manifest — i.e., the user hasn't run install_mac.sh yet
/// (or it hasn't finished). Polls every 5 s for the manifest to appear.
struct ConfigOnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 48)).foregroundStyle(.cyan)
            Text("WAITING FOR MAC SETUP")
                .font(.caption.monospaced().bold()).tracking(2)
            Text("On your Mac, run:\n\n`bash pipeline/install_mac.sh`\n\nThis app will refresh automatically.")
                .font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).padding(.horizontal, 32)
        }
        .padding()
        .onAppear {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in await store.applyLatestManifest() }
            }
        }
        .onDisappear { pollTimer?.invalidate() }
    }
}
