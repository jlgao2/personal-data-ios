import Foundation

/// Top-level bundle the laptop publishes to iCloud Drive on each refresh.
/// Mirrors the Python `publish_ios_export()` output shape.
struct IOSBundle: Codable {
    let exported_at: String
    let vitals: [String: VitalSeries]
    let workouts: [Workout]
    let action_loop: [ActionCard]
    let profile: HealthProfile?
}

struct VitalSeries: Codable {
    let series: [SeriesPoint]
    let latest: Double?
    let trend: String?
}

/// Series points are emitted as ["YYYY-MM-DD", value]. Decode with a custom init.
struct SeriesPoint: Codable {
    let date: String
    let value: Double

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        date  = try c.decode(String.self)
        value = try c.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(date)
        try c.encode(value)
    }
}

struct Workout: Codable, Identifiable {
    let ts_start: String
    let ts_end: String
    let label: String
    let sport: String?
    let duration_s: Double?
    let distance_m: Double?
    let calories: Double?
    let avg_hr: Double?
    let max_hr: Double?
    let training_load: Double?
    let aerobic_te: Double?
    let hr_zones: [String: Int]?

    var id: String { ts_start + label }
}

struct ActionCard: Codable, Identifiable {
    let finding_id: String
    let gene: String?
    let finding_summary: String?
    let finding_tier: String?
    let sample_type: String
    let expected_direction: String?
    let target_value: Double?
    let takeaway: String?
    let latest_value: Double?
    let latest_ts: String?
    let avg_90d: Double?

    var id: String { finding_id + sample_type }
}

struct HealthProfile: Codable {
    let supplement_stack: [Supplement]?
    let daily_protocol: [String: DayProtocol]?
    let prep_checklist_template: [String]?
    let medications_to_avoid: [MedAlert]?
    let current_medications: [String]?
    let active_conditions: ActiveConditions?
    let action_plan_immediate: [String]?
}

struct Supplement: Codable, Identifiable {
    let name: String
    let dose: String?
    let timing: String?
    let with_food: Bool?
    let rationale: String?
    let links: [String]?
    let evidence: String?

    var id: String { name }
}

struct DayProtocol: Codable {
    let session: String
    let rehab: [String]?
    let warmup: [String]?
    let main: [String]?
    let core: [String]?
}

struct MedAlert: Codable, Identifiable {
    let `class`: String
    let reason: String

    var id: String { `class` }
}

struct ActiveConditions: Codable {
    let lower_extremity: [String]?
    let upper_extremity: [String]?
}
