import Foundation

/// Spinoza's adequate-cause tag, surfaced per obligation. The user
/// long-presses an obligation card to mark whether it's a self-authored
/// requirement (it flows from their nature) or an outside requirement
/// (imposed, inherited, or by guilt). Outside-tagged obligations stay
/// visible — we don't pretend they're gone — but render dimly and stop
/// contributing to the DailyLock filled-count, so the streak doesn't
/// silently bribe you into honoring imposed obligations as if they
/// were yours.
///
/// The set of surfaces is intentionally bounded; new surfaces require
/// a deliberate decision about whether authorship applies.
enum Authorship: String, Codable, CaseIterable {
    case selfAuthored = "self"
    case outside
    case unset

    var label: String {
        switch self {
        case .selfAuthored: return "From your nature"
        case .outside:      return "From outside"
        case .unset:        return "Unset"
        }
    }
}

/// Stable string IDs for each authorship-tagged surface. Centralised so
/// callers can't typo a key.
enum AuthorshipSurface: String, CaseIterable {
    case workout, suppsAM = "supps_am", suppsPM = "supps_pm"
    case mindful, skincareAM = "skincare_am", skincarePM = "skincare_pm"
    case embodiment
}

enum AuthorshipStore {
    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static func key(_ surface: AuthorshipSurface) -> String {
        "authorship_\(surface.rawValue)"
    }

    static func get(_ surface: AuthorshipSurface) -> Authorship {
        guard let raw = defaults.string(forKey: key(surface)),
              let val = Authorship(rawValue: raw) else { return .unset }
        return val
    }

    static func set(_ surface: AuthorshipSurface, to authorship: Authorship) {
        if authorship == .unset {
            defaults.removeObject(forKey: key(surface))
        } else {
            defaults.set(authorship.rawValue, forKey: key(surface))
        }
        NotificationCenter.default.post(name: .authorshipDidChange, object: surface)
    }
}

extension Notification.Name {
    /// Fires when any surface's Authorship tag changes. Views observing
    /// authorship state (DailyLockChip's filled count, card opacity)
    /// subscribe to refresh in place.
    static let authorshipDidChange = Notification.Name("PrefrontalCortex.authorshipDidChange")
}
