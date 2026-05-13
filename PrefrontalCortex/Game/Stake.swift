import Foundation

/// A committed act with a named witness. The user declares what they'll
/// do in the current band, picks someone from their reach-out queue,
/// and ships a message to them via the share sheet. After the band's
/// deadline passes, the app prompts the user to close the loop with
/// the same witness (did, missed). The witness existing is what makes
/// the outcome un-pre-secureable — without one it's a private pre-game.
///
/// Single-stake invariant: at most one active stake per day. Vigor lives
/// in seeing one thing through, not in juggling commitments.
struct Stake: Codable, Equatable {
    enum Status: String, Codable {
        case pending      // committed, witness named, message not yet sent
        case declared     // share sheet completed — witness knows
        case completed    // user marked done
        case missed       // user marked missed (or deadline passed unresolved)
    }

    var prompt: String        // "Cook dinner without my phone"
    var witnessName: String   // Display name pulled from reach_out
    var bandRaw: String       // TimeBand.rawValue at the moment of commit
    var deadline: Date        // Defaults to the band's nextEdge
    var createdAt: Date
    var declaredAt: Date?
    var resolvedAt: Date?
    var status: Status
}

enum StakeStore {
    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static func key(date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "stake_\(f.string(from: date))"
    }

    static func load(date: Date = Date()) -> Stake? {
        guard let data = defaults.data(forKey: key(date: date)) else { return nil }
        return try? JSONDecoder().decode(Stake.self, from: data)
    }

    static func save(_ stake: Stake) {
        guard let data = try? JSONEncoder().encode(stake) else { return }
        defaults.set(data, forKey: key(date: stake.createdAt))
    }

    static func clear(date: Date = Date()) {
        defaults.removeObject(forKey: key(date: date))
    }
}
