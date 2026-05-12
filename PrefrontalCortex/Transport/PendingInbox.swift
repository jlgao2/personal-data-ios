import Foundation

/// Per-kind queue stored in the app sandbox for writes made while iCloud
/// was unavailable. Drained on the next successful container check.
enum PendingInbox {
    private static var dir: URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory,
                                        in: .userDomainMask, appropriateFor: nil,
                                        create: true) else { return nil }
        let d = support.appendingPathComponent("PendingInbox", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func enqueue<T: Encodable>(kind: String, rows: [T]) {
        guard !rows.isEmpty, let dir else { return }
        let file = dir.appendingPathComponent("\(kind)-\(UUID().uuidString).json")
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Iterates all queued batches for the given `kind`, decodes each into
    /// `[T]`, hands them to `handle`, and removes the file on success. If
    /// the handle throws, leaves the file in place so we'll retry next time.
    static func draining<T: Decodable>(kind: String,
                                       decoding: T.Type,
                                       handle: (T) async throws -> Void) async {
        guard let dir else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                          includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix("\(kind)-") {
            guard let data  = try? Data(contentsOf: f),
                  let batch = try? JSONDecoder().decode([T].self, from: data) else { continue }
            do {
                for row in batch { try await handle(row) }
                try? FileManager.default.removeItem(at: f)
            } catch {
                return  // leave file for next drain
            }
        }
    }
}
