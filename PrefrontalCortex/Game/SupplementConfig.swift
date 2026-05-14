import Foundation

/// User-edited supplement stack. Persisted at `iCloud config/supplements.json`.
/// Wraps the list (rather than being a bare `[Supplement]`) so the schema
/// can grow later — adding a `mode: "training" | "travel"` field for
/// context-specific stacks, for example, doesn't require touching every
/// existing caller.
struct SupplementConfig: Codable, Equatable {
    var supplements: [Supplement]

    static let empty = SupplementConfig(supplements: [])
}

/// Read/write wrapper around `iCloudTransport`. The store fires
/// `supplementsDidChange` on every successful save so display surfaces
/// (StackDetailView, StackView's PeriodButtons) can refresh in place
/// without a manual reload.
enum SupplementConfigStore {
    static func load() async -> SupplementConfig {
        if let c = try? await iCloudTransport.shared
            .readConfig(name: "supplements", as: SupplementConfig.self), let c {
            return c
        }
        return .empty
    }

    static func save(_ config: SupplementConfig) async throws {
        try await iCloudTransport.shared.writeConfig(name: "supplements", config)
        await MainActor.run {
            NotificationCenter.default.post(name: .supplementsDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    /// Fires after a successful write to `config/supplements.json`.
    /// Display surfaces that read the user-edited list listen and refresh.
    static let supplementsDidChange = Notification.Name("PrefrontalCortex.supplementsDidChange")
}
