import Foundation

/// Source of truth for transport configuration.
/// - serverURLString lives in App-Group UserDefaults so the widget can read it.
/// - token lives in Keychain (never UserDefaults, never the App Group).
@MainActor
final class TransportSettings: ObservableObject {
    static let shared = TransportSettings()

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let urlKey   = "transport.serverURL"
    private static let kcService = "com.jlgao.PrefrontalCortex.transport"
    private static let kcAccount = "bearer"

    private let defaults: UserDefaults

    @Published private(set) var serverURLString: String?
    @Published private(set) var token: String?

    private init() {
        let d = UserDefaults(suiteName: Self.appGroup) ?? .standard
        self.defaults = d
        self.serverURLString = d.string(forKey: Self.urlKey)
        self.token = Keychain.get(account: Self.kcAccount, service: Self.kcService)
    }

    var isConfigured: Bool {
        guard let s = serverURLString, URL(string: s) != nil,
              let t = token, !t.isEmpty else { return false }
        return true
    }

    var serverURL: URL? {
        guard let s = serverURLString else { return nil }
        return URL(string: s)
    }

    func update(serverURLString: String?, token: String?) throws {
        let trimmedURL = serverURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let u = trimmedURL, !u.isEmpty {
            defaults.set(u, forKey: Self.urlKey)
            self.serverURLString = u
        } else {
            defaults.removeObject(forKey: Self.urlKey)
            self.serverURLString = nil
        }

        if let t = trimmedToken, !t.isEmpty {
            try Keychain.set(t, account: Self.kcAccount, service: Self.kcService)
            self.token = t
        } else {
            Keychain.delete(account: Self.kcAccount, service: Self.kcService)
            self.token = nil
        }
    }
}
