import Foundation

@MainActor
final class TransportSettings: ObservableObject {
    static let shared = TransportSettings()
    private init() {}

    // Legacy keys explicitly cleared in Migrations.swift on first launch.
    // Only feature toggles remain (workout unit, med-alerts flag) and
    // those live in @AppStorage on the views that own them.
}
