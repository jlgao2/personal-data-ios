import Foundation

/// Top-level bundle the laptop publishes to iCloud Drive on each refresh.
/// Mirrors the Python `publish_ios_export()` output shape.
struct IOSBundle: Codable {
    let exported_at: String
    let vitals: [String: VitalSeries]
    let workouts: [Workout]
    let action_loop: [ActionCard]
    let profile: HealthProfile?
    let genomics: Genomics?
    let med_alerts: [MedAlertEvent]?
    let adapted_session: AdaptedSession?
    let social: SocialSummary?
    let calendar: [CalendarEvent]?
    let correlations: CorrelationsBundle?
    let deviations_summary: DeviationsSummary?
}

struct DeviationsSummary: Codable {
    let by_surface: [String: Int]?
    let total: Int?
}

struct CorrelationsBundle: Codable {
    let correlations: [CorrelationFinding]?
    let day_of_week: [DOWStat]?
}

struct CorrelationFinding: Codable, Identifiable {
    let name: String
    let n: Int
    let trend: String              // "positive" | "negative" | "neutral"
    let summary: String?
    let actionable: String?
    let metric_a: Double?
    let metric_b: Double?
    let metric_a_label: String?
    let metric_b_label: String?
    let unit: String?
    let r: Double?
    let table: [SportDelta]?

    var id: String { name }
}

struct SportDelta: Codable, Identifiable {
    let sport: String
    let n: Int
    let delta_rhr: Double

    var id: String { sport }
}

struct DOWStat: Codable, Identifiable {
    let dow: String                // "Mon" .. "Sun"
    let sleep: Double?             // minutes
    let rhr: Double?
    let tl: Double?                // training load
    let workouts: Int
    let n: Int

    var id: String { dow }
}

struct CalendarEvent: Codable, Identifiable {
    let id: String?
    let summary: String?
    let start: String?
    let end: String?
    let all_day: Bool?
    let location: String?
    let url: String?
}

struct SocialSummary: Codable {
    let generated: String?
    let today: String?
    let total_people: Int?
    let reach_out: [SocialPerson]?
    let birthdays: [SocialBirthday]?
}

struct SocialPerson: Codable, Identifiable {
    let id: String?
    let name: String?
    let attention_score: Int?
    let days_since_last: Int?
    let last_msg_from: String?
    let last_excerpt: String?
    let about_what: String?
    let sources: [String]?
    let msg_count: Int?
    let has_portrait: Bool?
}

struct SocialBirthday: Codable, Identifiable {
    let id: String?
    let name: String?
    let month: Int?
    let day: Int?
    let days_until: Int?
    let year_known: Bool?
}

struct AdaptedSession: Codable {
    let program_day: String?
    let prescribed: String?
    let traffic_light: String?         // "green" | "amber" | "red"
    let intensity_modifier: Double?
    let intensity_reason: String?
    let swaps: [SessionSwap]?
    let removed: [SessionItem]?
    let added: [SessionItem]?
    let notes: [String]?
    let rules_fired: [String]?
}

struct SessionSwap: Codable, Identifiable {
    let original: String
    let replacement: String
    let reason: String?
    var id: String { original }
}

struct SessionItem: Codable, Identifiable {
    let item: String
    let reason: String?
    var id: String { item }
}

struct MedAlertEvent: Codable, Identifiable {
    let medication: String
    let drug_class: String?
    let reason: String?
    let fhir_status: String?
    let started: String?
    let severity: String?

    var id: String { medication + (started ?? "") }
}

struct Genomics: Codable {
    let total: Int?
    let tier_counts: [String: Int]?
    let by_source: [String: [Finding]]?
}

struct Finding: Codable, Identifiable {
    let id: String
    let source_tsv: String
    let gene: String?
    let rsid: String?
    let chrom: String?
    let pos: Int?
    let ref: String?
    let alt: String?
    let genotype: String?
    let tier: String?
    let summary: String?
    // meta is omitted for now — JSON shape varies by source.
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
    let action_plan_short_term_4_to_8_weeks: [String]?
    let action_plan_medium_term_2_to_3_months: [String]?
    let action_plan_ongoing: [String]?
    let vision_statement: String?
    let goals: [Goal]?
    let abstinences: [Abstinence]?

    struct Abstinence: Codable, Identifiable {
        let key: String?
        let label: String
        var id: String { key ?? label }
    }
}

struct Goal: Codable, Identifiable {
    let name: String
    let current: Double?
    let target: Double?
    let baseline: Double?
    let units: String?
    let direction: String?      // "increase" | "decrease"
    let deadline: String?       // ISO date
    let category: String?
    let note: String?

    var id: String { name }
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
