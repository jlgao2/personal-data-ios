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

    private enum CodingKeys: String, CodingKey {
        case exported_at
        case vitals
        case workouts
        case action_loop
        case profile
        case genomics
        case med_alerts
        case adapted_session
        case social
        case calendar
        case correlations
        case deviations_summary
    }

    /// Resilient decode: each top-level field is decoded independently so a
    /// single malformed field doesn't brick the entire home screen. Nested
    /// Codable types (Workout, ActionCard, etc.) still throw on bad input —
    /// only this top-level swallows per-field decode errors.
    init(from decoder: Decoder) throws {
        // If the JSON isn't an object at all, fail outright — there's nothing
        // useful we can recover.
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func decodeField<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            do {
                return try c.decodeIfPresent(T.self, forKey: key)
            } catch {
                print("[IOSBundle] failed to decode field \(key.rawValue): \(error)")
                return nil
            }
        }

        // exported_at is non-optional but we'd rather render the rest of the
        // bundle with an empty timestamp than blank the whole screen.
        self.exported_at        = decodeField(String.self, .exported_at) ?? ""
        self.vitals             = decodeField([String: VitalSeries].self, .vitals) ?? [:]
        self.workouts           = decodeField([Workout].self, .workouts) ?? []
        self.action_loop        = decodeField([ActionCard].self, .action_loop) ?? []
        self.profile            = decodeField(HealthProfile.self, .profile)
        self.genomics           = decodeField(Genomics.self, .genomics)
        self.med_alerts         = decodeField([MedAlertEvent].self, .med_alerts)
        self.adapted_session    = decodeField(AdaptedSession.self, .adapted_session)
        self.social             = decodeField(SocialSummary.self, .social)
        self.calendar           = decodeField([CalendarEvent].self, .calendar)
        self.correlations       = decodeField(CorrelationsBundle.self, .correlations)
        self.deviations_summary = decodeField(DeviationsSummary.self, .deviations_summary)
    }
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
    // Structured cardio-modality recommendation for cardio-tagged days
    // (populated by `rule_cardio_modality_suggest`). nil when no rotation
    // pressure or the day isn't cardio. AdaptedSessionView renders a
    // cyan-stroked banner above the prescribed `main[]` when present.
    let cardio_suggestion: CardioSuggestion?
    // What you ACTUALLY did today (HealthKit/Garmin sessions). Lets the
    // workout card show what you did against the prescription instead
    // of only ever showing the plan.
    let completed_today: [CompletedWorkout]?
}

struct CompletedWorkout: Codable {
    let label: String?
    let sport: String?
    let duration_min: Int?
}

/// Single source of truth for how the workout reads — used by the Now
/// card AND the band Live Activity (via the widget snapshot) so they
/// can never diverge ("Train" on the lock screen while the card says
/// "Rest day" was exactly that drift).
extension AdaptedSession {
    var isRestDay: Bool {
        let p = (prescribed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty || p.lowercased() == "rest"
    }

    /// The act, named concretely from the prescribed string: the lead
    /// segment before the first separator. "Yoga · hip openers…" →
    /// "Yoga"; "Sport / outdoor (no running)" → "Sport"; "Push + core"
    /// stays whole; rest → "Rest day".
    var workoutTitle: String {
        if isRestDay { return "Rest day" }
        let presc = (prescribed ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !presc.isEmpty else { return "Train" }
        for sep in [" · ", " / ", " — ", ", "] {
            if let r = presc.range(of: sep) {
                let head = presc[..<r.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                if !head.isEmpty { return head }
            }
        }
        return presc
    }

    /// Subtext: what you actually did wins (the title still shows the
    /// plan, so "Rest day / Did: Cycling · 190 min" reads as the
    /// contrast it is), else the rest note, else the adaptive headline.
    var workoutDetail: String {
        let did = completedSummary
        if !did.isEmpty { return did }
        if isRestDay {
            return notes?.first ?? "Recovery: walk, mobility, sleep ≥7h."
        }
        return adaptiveHeadline
    }

    /// "Did: Cycling · 190 min" from HealthKit/Garmin sessions. Empty
    /// when nothing's logged yet.
    var completedSummary: String {
        guard let done = completed_today, !done.isEmpty else { return "" }
        let parts = done.map { w -> String in
            let name = w.sport.map {
                $0.replacingOccurrences(of: "_", with: " ").capitalized
            } ?? w.label ?? "Workout"
            if let m = w.duration_min, m > 0 { return "\(name) · \(m) min" }
            return name
        }
        return "Did: " + parts.joined(separator: ", ")
    }

    /// Traffic light + intensity delta + swap count — the adaptive
    /// layer ("Green · full intensity", "Amber · −20% · 1 swap").
    var adaptiveHeadline: String {
        var parts: [String] = []
        switch (traffic_light ?? "").lowercased() {
        case "green": parts.append("Green")
        case "amber": parts.append("Amber")
        case "red":   parts.append("Red")
        default: break
        }
        if let m = intensity_modifier {
            if abs(m - 1.0) < 0.001 {
                if !parts.isEmpty { parts.append("full intensity") }
            } else if m < 1.0 {
                parts.append("−\(Int((1.0 - m) * 100 + 0.5))%")
            } else {
                parts.append("+\(Int((m - 1.0) * 100 + 0.5))%")
            }
        }
        if let n = swaps?.count, n > 0 {
            parts.append("\(n) swap\(n == 1 ? "" : "s")")
        }
        if parts.isEmpty {
            return notes?.first ?? "Today's prescribed session."
        }
        return parts.joined(separator: " · ")
    }
}

/// Sidecar suggestion for cardio days — the engine emphasizes which
/// curated modality fits this week's spread without rewriting the
/// prescribed list. `from_prescribed` is true when `modality` already
/// appears in today's curated `main[]`; false when engine-introduced
/// (e.g. swimming substituted for running under a peroneal condition).
struct CardioSuggestion: Codable {
    let modality: String                // "swimming" | "cycling" | "running"
    let reason: String
    let from_prescribed: Bool
    let alternatives: [String]?
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
    /// Optional — emitted by `data/health_profile.json` after the durable
    /// refactor on the laptop side. Values: "rest" | "light" | "moderate"
    /// | "heavy". Drives whether the iOS-side UX surfaces "did different"
    /// vs "outside plan" pre-fills when today's HK workout doesn't match
    /// the prescription.
    let intensity_class: String?
    let tags: [String]?
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
