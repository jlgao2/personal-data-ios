import Foundation

struct SampleUpload: Codable {
    let ts: String
    let type: String
    let value: Double
    let unit: String?
}

/// Typed contract for `POST /v1/sessions`. Field names match what
/// `pipeline/parsers/ios_sessions.py` expects on the laptop, so the JSON
/// shape produced by `JSONEncoder` is the wire format — no manual dict
/// assembly. If you add a field here, mirror it in the parser.
struct SessionUpload: Codable {
    let client_id: String
    let ts: String            // ISO8601
    let sport: String         // UPPER_SNAKE (e.g. "CYCLING")
    let duration_min: Int
    let rpe: Int?
    let note: String
}

struct DeviationUpload: Codable {
    let client_id: String
    let ts: String
    let surface: String
    let surface_id: String?
    let direction: String
    let cause: String?
    let prescribed: String
    let actual: String
    let actual_quant: Double?
    let lock_in: Bool
    let note: String?
}
