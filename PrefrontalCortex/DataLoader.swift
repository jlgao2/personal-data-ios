import Foundation

enum DataError: Error {
    case noICloud
    case noBundleFile
}

final class DataLoader {
    static let shared = DataLoader()

    /// iCloud Drive container ID. Must match the entitlement.
    private let containerID = "iCloud.com.jlgao.PrefrontalCortex"

    func iCloudURL() -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: containerID)?
            .appendingPathComponent("Documents/ios_export/ios_bundle.json")
    }

    /// Read the latest bundle the laptop pipeline published.
    /// Falls back to the bundled sample JSON if iCloud isn't ready (first launch / simulator).
    func loadBundle() async throws -> IOSBundle {
        if let url = iCloudURL() {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            // Crude wait for sync. Replace with NSMetadataQuery later.
            for _ in 0..<10 {
                if FileManager.default.fileExists(atPath: url.path) {
                    let data = try Data(contentsOf: url)
                    return try JSONDecoder().decode(IOSBundle.self, from: data)
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        // Fallback: sample bundled in the app for development
        if let sample = Bundle.main.url(forResource: "sample_bundle", withExtension: "json") {
            let data = try Data(contentsOf: sample)
            return try JSONDecoder().decode(IOSBundle.self, from: data)
        }
        throw DataError.noBundleFile
    }
}
