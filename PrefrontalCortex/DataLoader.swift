import Foundation

final class DataLoader {
    static let shared = DataLoader()

    private var cacheURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent("last_bundle.json")
    }

    /// Load the latest bundle from the laptop, falling back to last cache,
    /// then to the bundled sample. Throws on configured-but-failing transport.
    func loadBundle() async throws -> IOSBundle {
        let isConfigured = await TransportSettings.shared.isConfigured
        if isConfigured {
            do {
                let data = try await TransportClient.shared.fetchBundle()
                let bundle = try JSONDecoder().decode(IOSBundle.self, from: data)
                if let url = cacheURL { try? data.write(to: url, options: .atomic) }
                return bundle
            } catch {
                if let url = cacheURL,
                   let data = try? Data(contentsOf: url),
                   let cached = try? JSONDecoder().decode(IOSBundle.self, from: data) {
                    return cached
                }
                throw TransportClient.wrap(error)
            }
        }

        if let sample = Bundle.main.url(forResource: "sample_bundle", withExtension: "json") {
            let data = try Data(contentsOf: sample)
            return try JSONDecoder().decode(IOSBundle.self, from: data)
        }
        throw TransportError.notConfigured
    }
}
