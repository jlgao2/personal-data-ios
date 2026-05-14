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

extension iCloudTransport {

    /// Read-merge-rewrite for a date-keyed inbox file. Dedupe key is
    /// `client_id` for sessions/deviations; `(ts, type)` for samples.
    /// Caller passes a closure that extracts the dedupe key from a row.
    func uploadInbox<T: Codable>(
        kind: String,
        rows: [T],
        dedupeKey: (T) -> String
    ) async throws {
        guard !rows.isEmpty else { return }
        guard let url = iCloudPaths.inboxFile(kind: kind, date: Date()) else {
            throw iCloudTransportError.containerUnavailable
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        try await coordinatedReadModifyWrite(url) { existingData -> Data in
            var existing: [T] = []
            if let existingData,
               let decoded = try? JSONDecoder().decode([T].self, from: existingData) {
                existing = decoded
            }
            let seen = Set(existing.map(dedupeKey))
            let merged = existing + rows.filter { !seen.contains(dedupeKey($0)) }
            return try JSONEncoder().encode(merged)
        }
    }

    /// Public convenience matching today's TransportClient API.
    func uploadSamples(_ rows: [SampleUpload]) async throws {
        guard iCloudPaths.isAvailable else {
            PendingInbox.enqueue(kind: "samples", rows: rows)
            throw iCloudTransportError.containerUnavailable
        }
        try await uploadInbox(kind: "samples", rows: rows, dedupeKey: { "\($0.ts)|\($0.type)" })
    }
    func uploadSessions(_ rows: [SessionUpload]) async throws {
        guard iCloudPaths.isAvailable else {
            PendingInbox.enqueue(kind: "sessions", rows: rows)
            throw iCloudTransportError.containerUnavailable
        }
        try await uploadInbox(kind: "sessions", rows: rows, dedupeKey: { $0.client_id })
    }
    func uploadDeviations(_ rows: [DeviationUpload]) async throws {
        guard iCloudPaths.isAvailable else {
            PendingInbox.enqueue(kind: "deviations", rows: rows)
            throw iCloudTransportError.containerUnavailable
        }
        try await uploadInbox(kind: "deviations", rows: rows, dedupeKey: { $0.client_id })
    }

    // MARK: - User config (iOS-side edits the laptop pipeline reads)

    /// Read a typed config file from `config/<name>.json`. Returns
    /// `nil` if the file doesn't exist yet (first-time read; the user
    /// hasn't configured this surface). Throws on container unavailable
    /// or decode failure — caller decides whether to fall back to a
    /// default or surface the error.
    func readConfig<T: Codable>(name: String, as type: T.Type) async throws -> T? {
        guard let url = iCloudPaths.configFile(name: name) else {
            throw iCloudTransportError.containerUnavailable
        }
        do {
            let data = try await coordinatedRead(url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch iCloudTransportError.fileMissing {
            return nil
        }
    }

    /// Write a typed value to `config/<name>.json`, overwriting any
    /// existing content. Coordinated write via the same atomic-replace
    /// path the inbox writers use. The laptop pipeline picks up the
    /// new content on its next refresh.
    func writeConfig<T: Codable>(name: String, _ value: T) async throws {
        guard let url = iCloudPaths.configFile(name: name) else {
            throw iCloudTransportError.containerUnavailable
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try await coordinatedReadModifyWrite(url) { _ in data }
    }

    /// Read-merge-rewrite for a typed config file. The transform sees
    /// the current value (nil if missing) and returns the next value.
    /// Use this when the new content depends on what's already there
    /// — e.g., "append this swap to the existing swap list" — so two
    /// concurrent edits (phone + laptop) don't lose data.
    func updateConfig<T: Codable>(name: String,
                                  as type: T.Type,
                                  _ transform: @escaping (T?) -> T) async throws {
        guard let url = iCloudPaths.configFile(name: name) else {
            throw iCloudTransportError.containerUnavailable
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await coordinatedReadModifyWrite(url) { existingData in
            let current: T? = existingData.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
            let next = transform(current)
            return try JSONEncoder().encode(next)
        }
    }

    // MARK: - Internals

    private func coordinatedReadModifyWrite(
        _ url: URL,
        _ transform: (Data?) throws -> Data
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let coord = NSFileCoordinator(filePresenter: nil)
            var err: NSError?
            coord.coordinate(writingItemAt: url, options: .forReplacing,
                              error: &err) { resolved in
                do {
                    let existing = try? Data(contentsOf: resolved)
                    let next = try transform(existing)
                    let tmp = resolved.appendingPathExtension("tmp")
                    try next.write(to: tmp, options: .atomic)
                    _ = try FileManager.default.replaceItemAt(resolved, withItemAt: tmp)
                    cont.resume(returning: ())
                } catch {
                    cont.resume(throwing: error)
                }
            }
            if let err {
                cont.resume(throwing: iCloudTransportError.coordinationFailed(err))
            }
        }
    }
}

extension iCloudTransport {
    /// List backup directories newest-first. Returns directory NAMES (ISO timestamps).
    func listBackups() throws -> [String] {
        guard let dir = iCloudPaths.backupsDir else {
            throw iCloudTransportError.containerUnavailable
        }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { $0.lastPathComponent }
            .sorted(by: >)
    }

    /// Copy each `*.json` from `backups/<id>/` over `config/`.
    func restoreBackup(_ id: String) async throws {
        guard let backupsDir = iCloudPaths.backupsDir,
              let configDir  = iCloudPaths.configDir else {
            throw iCloudTransportError.containerUnavailable
        }
        let src = backupsDir.appendingPathComponent(id)
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            let dest = configDir.appendingPathComponent(f.lastPathComponent)
            _ = try? fm.replaceItemAt(dest, withItemAt: f)
        }
    }
}
