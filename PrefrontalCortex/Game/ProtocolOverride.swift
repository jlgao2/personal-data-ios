import Foundation

/// User edits to the prescribed training protocol — the end-user path
/// for changes like "add glute medius to Day 1 prehab" that previously
/// required hand-editing health_profile.json.
///
/// Replace-semantics, not a diff: when the user edits a section we
/// store their full desired list for that (day, section). The laptop
/// pipeline, on its next refresh, substitutes any present override
/// section into the generated daily_protocol; absent sections fall
/// through to whatever the engine prescribed. Mirrors the
/// weekly_rhythm / supplements config pattern.
///
/// Persisted at `iCloud config/protocol_overrides.json`. The Python
/// reader that consumes it is the same follow-up as the rhythm/supps
/// readers — until it lands, edits are durable + visible on the phone
/// but don't yet alter the generated bundle.
struct ProtocolOverride: Codable {
    /// "Day 1" → "rehab" → ["Eccentric eversion …", "Banded lateral …"]
    var sections: [String: [String: [String]]]

    static let empty = ProtocolOverride(sections: [:])

    func list(day: String, section: String) -> [String]? {
        sections[day]?[section]
    }

    mutating func set(day: String, section: String, _ items: [String]) {
        sections[day, default: [:]][section] = items
    }

    mutating func clear(day: String, section: String) {
        sections[day]?.removeValue(forKey: section)
        if sections[day]?.isEmpty == true { sections.removeValue(forKey: day) }
    }
}

enum ProtocolOverrideStore {
    static func load() async -> ProtocolOverride {
        if let c = try? await iCloudTransport.shared
            .readConfig(name: "protocol_overrides", as: ProtocolOverride.self) {
            return c
        }
        return .empty
    }

    static func save(_ o: ProtocolOverride) async throws {
        try await iCloudTransport.shared.writeConfig(name: "protocol_overrides", o)
        await MainActor.run {
            NotificationCenter.default.post(name: .protocolOverridesDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let protocolOverridesDidChange =
        Notification.Name("PrefrontalCortex.protocolOverridesDidChange")
}
