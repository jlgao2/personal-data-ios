import XCTest
@testable import PrefrontalCortex

final class iCloudTransportTests: XCTestCase {
    func test_manifest_decodes_with_required_fields() throws {
        let json = """
        {
          "schema_version": "1.0",
          "exported_at":    "2026-05-11T03:24:46Z",
          "bundle_sha256":  "abc",
          "source_hashes":  {"config/health_profile.json": "def"},
          "pipeline_version": "test",
          "status": "ok"
        }
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(Manifest.self, from: json)
        XCTAssertEqual(m.status, "ok")
        XCTAssertEqual(m.bundle_sha256, "abc")
        XCTAssertTrue(m.isOk)
    }
}
