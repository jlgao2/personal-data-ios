import XCTest
@testable import PrefrontalCortex

final class BundleDecodeTests: XCTestCase {
    func test_one_bad_field_doesnt_brick_the_bundle() throws {
        let json = """
        {
          "exported_at": "2026-05-11T00:00:00Z",
          "vitals": "GARBAGE_NOT_A_DICT",
          "workouts": [],
          "action_loop": []
        }
        """.data(using: .utf8)!
        let bundle = try JSONDecoder().decode(IOSBundle.self, from: json)
        XCTAssertEqual(bundle.vitals, [:])      // defaulted because decode failed
        XCTAssertEqual(bundle.workouts.count, 0)
        XCTAssertEqual(bundle.exported_at, "2026-05-11T00:00:00Z")
    }
}
