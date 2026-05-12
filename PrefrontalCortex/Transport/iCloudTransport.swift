import Foundation

enum iCloudTransportError: Error, LocalizedError {
    case containerUnavailable
    case fileMissing(URL)
    case readFailed(URL, Error)
    case decodeFailed(URL, Error)
    case coordinationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:        return "iCloud container not available."
        case .fileMissing(let u):          return "Missing: \(u.lastPathComponent)"
        case .readFailed(let u, let e):    return "Read failed (\(u.lastPathComponent)): \(e.localizedDescription)"
        case .decodeFailed(let u, let e):  return "Decode failed (\(u.lastPathComponent)): \(e.localizedDescription)"
        case .coordinationFailed(let e):   return "File coordination failed: \(e.localizedDescription)"
        }
    }
}

final class iCloudTransport {
    static let shared = iCloudTransport()

    /// Fetch the latest manifest. Coordinated read; downloads on demand.
    func fetchManifest() async throws -> Manifest {
        let url = try ensureURL(iCloudPaths.manifestURL)
        let data = try await coordinatedRead(url)
        do { return try JSONDecoder().decode(Manifest.self, from: data) }
        catch { throw iCloudTransportError.decodeFailed(url, error) }
    }

    /// Fetch the bundle as raw Data. Caller decodes into `IOSBundle`.
    func fetchBundle() async throws -> Data {
        let url = try ensureURL(iCloudPaths.bundleURL)
        return try await coordinatedRead(url)
    }

    // MARK: - Internals

    private func ensureURL(_ url: URL?) throws -> URL {
        guard let url else { throw iCloudTransportError.containerUnavailable }
        return url
    }

    /// Wraps NSFileCoordinator + on-demand iCloud download.
    private func coordinatedRead(_ url: URL) async throws -> Data {
        try await startDownloadIfNeeded(url)
        return try await withCheckedThrowingContinuation { cont in
            let coord = NSFileCoordinator(filePresenter: nil)
            var coordError: NSError?
            coord.coordinate(readingItemAt: url, options: [], error: &coordError) { resolved in
                do {
                    let data = try Data(contentsOf: resolved)
                    cont.resume(returning: data)
                } catch {
                    cont.resume(throwing: iCloudTransportError.readFailed(resolved, error))
                }
            }
            if let coordError {
                cont.resume(throwing: iCloudTransportError.coordinationFailed(coordError))
            }
        }
    }

    private func startDownloadIfNeeded(_ url: URL) async throws {
        let keys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey]
        let values = try? url.resourceValues(forKeys: keys)
        let status = values?.ubiquitousItemDownloadingStatus
        if status == .current { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        // Poll with backoff (1s, 5s, 25s) for the download to land.
        for delay in [1.0, 5.0, 25.0] {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let v = try? url.resourceValues(forKeys: keys)
            if v?.ubiquitousItemDownloadingStatus == .current { return }
        }
        throw iCloudTransportError.fileMissing(url)
    }
}
