import Foundation

/// Idempotent one-shot init called from AppStore.bootstrap. Clears the
/// legacy bearer-token + URL keys from UserDefaults so the old
/// TransportSettings storage doesn't linger as dead state.
enum Migrations {
    private static let flagKey = "did_migrate_to_icloud_v1"

    @MainActor
    static func runIfNeeded(into store: AppStore) {
        let d = UserDefaults.standard
        guard !d.bool(forKey: flagKey) else { return }
        d.removeObject(forKey: "transport_server_url")
        d.removeObject(forKey: "transport_token")
        d.set(true, forKey: flagKey)
        store.lastUploadResult = "Moved to iCloud sync. Old laptop pairing was cleared."
    }
}
