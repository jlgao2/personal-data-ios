import Foundation

/// Mirrors `pipeline/manifest_writer.py`. Decoded from outbox/manifest.json
/// every time `refresh.sh` writes a new one. iOS watches THIS file (small)
/// instead of the bundle (~600 KB) to know when to refresh.
struct Manifest: Codable, Equatable {
    let schema_version:   String
    let exported_at:      String
    let bundle_sha256:    String?
    let source_hashes:    [String: String]
    let pipeline_version: String
    let status:           String        // "ok" | "error"
    let error:            String?

    var isOk: Bool { status == "ok" }
}
