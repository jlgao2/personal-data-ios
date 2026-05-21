import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Calendar-driven load signal. Detects PT/Physio, travel, surgery,
/// dental, illness, vaccination, race contexts in the user's calendar
/// — the categories where today's workout should be different from
/// baseline (taper, rest, save the legs, jet-lag-adjusted, race day).
///
/// Two paths, in priority order:
///   1. iOS 26+ with Apple Intelligence available → on-device
///      Foundation Model with a @Generable schema (one bool per
///      category × time-relation + a short evidence quote). Handles
///      the nuance keywords miss: "rescheduled marathon", "extraction"
///      → dental, "got my booster", "PT" as a person's initials vs
///      Physical Therapy.
///   2. Below iOS 26 or model unavailable on the device → keyword +
///      date scan. Coarser but deterministic.
///
/// Output flows two places:
///   - `NowFocusView` splices `hint(signal)` into the workout card
///     detail so the user sees WHY today reads "easy".
///   - `AppStore` writes the Signal JSON to iCloud
///     `inbox/calendar_signal_<date>.json` so the laptop pipeline can
///     fold it into adaptive rules on the next refresh. The pipeline,
///     not iOS, owns the actual intensity_modifier — iOS only observes
///     and reports; the laptop adjudicates against everything else
///     (sleep, RHR, TL).
enum CalendarLoadDetector {
    enum Kind: String, Codable, Equatable, CaseIterable {
        case pt, travel, surgery, dental, illness, vaccination, race
    }
    enum When: String, Codable, Equatable, CaseIterable {
        case attendedToday          // happened earlier today (or all-day today)
        case scheduledLaterToday    // happens later today (after now)
        case attendedYesterday      // happened yesterday
        case recent                 // within last 7 days (surgery / vaccine / dental / travel)
        case scheduledThisWeek      // within next 7 days, NOT today
    }

    struct Detection: Codable, Equatable {
        let kind: Kind
        let when: When
        let evidence: String
    }

    /// What we ship to the inbox. JSON shape:
    /// `{"computed_at":"...","local_date":"YYYY-MM-DD",
    ///   "model_source":"foundation_models"|"keyword",
    ///   "detections":[{"kind":"pt","when":"attendedToday","evidence":"..."}]}`
    struct Signal: Codable, Equatable {
        let computed_at: String
        let local_date: String
        let model_source: String
        let detections: [Detection]

        /// The single most-relevant detection for the workout-card hint.
        /// Priority is "what most warrants a taper today" — rest beats
        /// taper beats easy. Race-today is the one inversion (don't
        /// taper for a race, just go run it).
        var primary: Detection? {
            let priority: [(Kind, When)] = [
                (.illness, .attendedToday),
                (.surgery, .attendedToday),
                (.race, .attendedToday),
                (.race, .scheduledLaterToday),
                (.surgery, .recent),
                (.vaccination, .recent),
                (.pt, .attendedToday),
                (.pt, .scheduledLaterToday),
                (.travel, .attendedToday),
                (.travel, .scheduledLaterToday),
                (.dental, .recent),
                (.dental, .attendedYesterday),
                (.pt, .attendedYesterday),
                (.travel, .recent),
                (.race, .scheduledThisWeek),
                (.pt, .scheduledThisWeek),
                (.travel, .scheduledThisWeek),
            ]
            for (k, w) in priority {
                if let d = detections.first(where: { $0.kind == k && $0.when == w }) {
                    return d
                }
            }
            return detections.first
        }
    }

    /// Look at the calendar window (-7d → +14d) and return the signal.
    /// Returns nil only when the input has no events at all; the empty-
    /// detections case is a positive "nothing PT/travel/etc" result.
    static func detect(
        from events: [CalendarEvent],
        now: Date = Date()
    ) async -> Signal? {
        guard !events.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        let stamp = iso.string(from: now)
        let dateF = DateFormatter()
        dateF.dateFormat = "yyyy-MM-dd"
        let localDate = dateF.string(from: now)

        if #available(iOS 26.0, macOS 26.0, *) {
            #if canImport(FoundationModels)
            if let dets = await foundationModelDetect(events: events, now: now) {
                return Signal(
                    computed_at: stamp,
                    local_date: localDate,
                    model_source: "foundation_models",
                    detections: dets
                )
            }
            #endif
        }
        return Signal(
            computed_at: stamp,
            local_date: localDate,
            model_source: "keyword",
            detections: keywordDetect(events: events, now: now)
        )
    }

    /// Human hint for the workout-card detail. Nil when no detection
    /// warrants a hint for today (e.g. only "race next Saturday" is on
    /// the calendar and today isn't taper week yet).
    static func hint(_ signal: Signal?) -> String? {
        guard let d = signal?.primary else { return nil }
        switch (d.kind, d.when) {
        case (.illness, _):                    return "Sick today — rest, no training."
        case (.surgery, .attendedToday):       return "Post-procedure — rest only."
        case (.surgery, .recent):              return "Recent procedure — light load."
        case (.race, .attendedToday):          return "Race today — just race."
        case (.race, .scheduledLaterToday):    return "Race later today — save your legs."
        case (.race, .scheduledThisWeek):      return "Race week — taper."
        case (.vaccination, .recent):          return "Recent vaccine — easy 24–48h."
        case (.pt, .attendedToday):            return "PT today — taper load."
        case (.pt, .scheduledLaterToday):      return "PT later today — save some legs."
        case (.pt, .attendedYesterday):        return "PT yesterday — keep it easy."
        case (.travel, .attendedToday),
             (.travel, .scheduledLaterToday):  return "Travel today — keep it light."
        case (.travel, .recent):               return "Jet lag — light load."
        case (.dental, _):                     return "Post-dental — easy."
        default:                               return nil
        }
    }

    // MARK: - Foundation Models path

    #if canImport(FoundationModels)
    /// Plain-bool dump is what Foundation Models is most reliable at —
    /// each @Guide is a yes/no the model can answer independently
    /// without having to coordinate a single enum choice across many
    /// categories. We translate the bools into the higher-level
    /// `Detection` list ourselves.
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    fileprivate struct CalendarLoadAssessment {
        @Guide(description: "PT/Physio/Rehab session attended earlier today (its time is in the past, or it's all-day today)")
        let ptAttendedToday: Bool
        @Guide(description: "PT/Physio/Rehab session scheduled later today (its start time is after now)")
        let ptScheduledLaterToday: Bool
        @Guide(description: "PT/Physio/Rehab session attended yesterday")
        let ptAttendedYesterday: Bool
        @Guide(description: "PT/Physio/Rehab session scheduled within next 7 days, NOT today")
        let ptScheduledThisWeek: Bool

        @Guide(description: "Travel today: long flight (≥3h), long drive (≥4h), or time-zone shift today")
        let travelToday: Bool
        @Guide(description: "Travel within the last 2 days — jet lag still affecting")
        let travelRecent: Bool
        @Guide(description: "Travel scheduled in the next 2 days")
        let travelScheduledSoon: Bool

        @Guide(description: "Surgery / procedure involving anesthesia within the last 14 days (NOT routine appointments)")
        let surgeryRecent: Bool
        @Guide(description: "Surgery / procedure with anesthesia scheduled today")
        let surgeryToday: Bool

        @Guide(description: "Dental procedure or extraction today or yesterday — NOT routine cleaning / check-up")
        let dentalRecent: Bool

        @Guide(description: "Calendar mentions illness today: flu, cold, fever, sick day, doctor visit specifically for illness")
        let illnessToday: Bool

        @Guide(description: "Vaccination, booster, or immunization within the last 2 days")
        let vaccinationRecent: Bool

        @Guide(description: "Race / competition / event today: 5K, 10K, half-marathon, marathon, triathlon, climbing comp, etc.")
        let raceToday: Bool
        @Guide(description: "Race / competition within the next 7 days but NOT today (taper period)")
        let raceThisWeek: Bool

        @Guide(description: "Short evidence quote — the calendar line that drove the strongest signal. Empty string if none of the above are true.")
        let evidence: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func foundationModelDetect(
        events: [CalendarEvent], now: Date
    ) async -> [Detection]? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        // Trim to window -7d → +14d. Surgery/vaccine recency cares about
        // the past week; race week cares about the next two weeks.
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let lo = cal.date(byAdding: .day, value: -7, to: today),
              let hi = cal.date(byAdding: .day, value: 14, to: today) else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = events.compactMap { e -> String? in
            guard let summary = e.summary, !summary.isEmpty else { return nil }
            guard let ss = e.start,
                  let when = iso.date(from: ss) ?? isoFrac.date(from: ss),
                  when >= lo, when <= hi else { return nil }
            let stamp = iso.string(from: when)
            let loc = e.location.map { " · \($0)" } ?? ""
            return "\(stamp) · \(summary)\(loc)"
        }.joined(separator: "\n")
        guard !lines.isEmpty else { return [] }

        let nowStamp = iso.string(from: now)
        let instructions = """
        You classify a user's calendar for load-affecting context. \
        "Now" is \(nowStamp). \
        Return booleans per category — read each event and decide.
        Categories:
        - PT/Physio/Rehab: PT, Physio, Physical Therapy, Physiotherapy, Rehab. Treat "PT" as Physical Therapy ONLY when it stands alone (not part of "captain", "computer", initials of a person).
        - Travel: long flight (≥3h), long drive (≥4h), time-zone shift. NOT a 1-hour drive to a meeting.
        - Surgery: anesthesia involved. NOT routine appointments or check-ups.
        - Dental: extraction or procedure. NOT routine cleaning.
        - Illness: a "sick day" event, fever/cold/flu mention, doctor visit specifically for being sick.
        - Vaccination: shots, boosters, immunizations.
        - Race: 5K, 10K, half-marathon, marathon, triathlon, climbing comp, etc.
        Provide one short evidence quote from the strongest signal's event.
        """
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Calendar events:\n\(lines)",
                generating: CalendarLoadAssessment.self
            )
            return mapAssessment(response.content)
        } catch {
            // On-device call still has failure modes (rate limit, schema
            // mismatch). Fall back to keyword path so the card still
            // gets a hint and the pipeline still gets a signal.
            print("CalendarLoadDetector FM call failed: \(error)")
            return nil
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func mapAssessment(_ a: CalendarLoadAssessment) -> [Detection] {
        var out: [Detection] = []
        let ev = a.evidence
        if a.ptAttendedToday        { out.append(.init(kind: .pt, when: .attendedToday, evidence: ev)) }
        if a.ptScheduledLaterToday  { out.append(.init(kind: .pt, when: .scheduledLaterToday, evidence: ev)) }
        if a.ptAttendedYesterday    { out.append(.init(kind: .pt, when: .attendedYesterday, evidence: ev)) }
        if a.ptScheduledThisWeek    { out.append(.init(kind: .pt, when: .scheduledThisWeek, evidence: ev)) }
        if a.travelToday            { out.append(.init(kind: .travel, when: .attendedToday, evidence: ev)) }
        if a.travelRecent           { out.append(.init(kind: .travel, when: .recent, evidence: ev)) }
        if a.travelScheduledSoon    { out.append(.init(kind: .travel, when: .scheduledThisWeek, evidence: ev)) }
        if a.surgeryToday           { out.append(.init(kind: .surgery, when: .attendedToday, evidence: ev)) }
        if a.surgeryRecent          { out.append(.init(kind: .surgery, when: .recent, evidence: ev)) }
        if a.dentalRecent           { out.append(.init(kind: .dental, when: .recent, evidence: ev)) }
        if a.illnessToday           { out.append(.init(kind: .illness, when: .attendedToday, evidence: ev)) }
        if a.vaccinationRecent      { out.append(.init(kind: .vaccination, when: .recent, evidence: ev)) }
        if a.raceToday              { out.append(.init(kind: .race, when: .attendedToday, evidence: ev)) }
        if a.raceThisWeek           { out.append(.init(kind: .race, when: .scheduledThisWeek, evidence: ev)) }
        return out
    }
    #endif

    // MARK: - Keyword fallback

    /// Deterministic scan. Used on iOS < 26 OR when the FM call fails.
    /// Conservative on "PT" abbreviation: only matches `\bpt\b` so
    /// "captain"/"compute" don't trigger; other terms match by phrase.
    private static func keywordDetect(events: [CalendarEvent], now: Date) -> [Detection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
              let weekAhead = cal.date(byAdding: .day, value: 7, to: today),
              let weekBehind = cal.date(byAdding: .day, value: -7, to: today),
              let twoWeeksAhead = cal.date(byAdding: .day, value: 14, to: today) else {
            return []
        }
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // (kind, phrases, word-bounded abbreviations).
        let dict: [(Kind, [String], [String])] = [
            (.pt,           ["physiotherapy", "physical therapy", "physio", "rehab"], ["pt"]),
            (.travel,       ["flight", "airport", "boarding", "departure", "layover", "red-eye"], []),
            (.surgery,      ["surgery", "operation", "procedure", "anesthesia", "post-op"], []),
            (.dental,       ["dental", "extraction", "wisdom tooth", "root canal"], []),
            (.illness,      ["sick day", " flu ", "fever", "covid", "doctor for"], []),
            (.vaccination,  ["vaccin", "immuniz", "booster", "flu shot"], []),
            (.race,         ["race", "5k", "10k", "half marathon", "marathon", "triathlon", "ultra"], []),
        ]
        // Which kinds recognize the .recent window (vs only same-day).
        let recencyAware: Set<Kind> = [.surgery, .vaccination, .dental, .travel]

        var out: [Detection] = []
        for e in events {
            guard let s = e.summary else { continue }
            let blob = (" " + s + " " + (e.location ?? "") + " ").lowercased()
            guard let ss = e.start,
                  let when = iso.date(from: ss) ?? isoFrac.date(from: ss) else { continue }
            let day = cal.startOfDay(for: when)

            for (kind, phrases, abbrevs) in dict {
                var matched = phrases.contains(where: { blob.contains($0) })
                if !matched {
                    for ab in abbrevs {
                        if blob.range(of: "\\b\(ab)\\b", options: .regularExpression) != nil {
                            matched = true; break
                        }
                    }
                }
                guard matched else { continue }
                let evidence = s

                if day == today {
                    let endDate: Date? = e.end.flatMap { iso.date(from: $0) ?? isoFrac.date(from: $0) }
                    let isPast = endDate.map { $0 <= now } ?? (when <= now)
                    out.append(.init(kind: kind, when: isPast ? .attendedToday : .scheduledLaterToday, evidence: evidence))
                } else if day == yesterday {
                    out.append(.init(kind: kind, when: .attendedYesterday, evidence: evidence))
                } else if day > today && day <= weekAhead {
                    out.append(.init(kind: kind, when: .scheduledThisWeek, evidence: evidence))
                } else if day < today && day >= weekBehind && recencyAware.contains(kind) {
                    out.append(.init(kind: kind, when: .recent, evidence: evidence))
                } else if kind == .surgery && day > today && day <= twoWeeksAhead {
                    out.append(.init(kind: kind, when: .scheduledThisWeek, evidence: evidence))
                }
            }
        }
        return out
    }
}
