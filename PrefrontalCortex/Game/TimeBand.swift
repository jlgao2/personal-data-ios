import Foundation
import SwiftUI

/// Time-of-day "band" that drives the Now tab's Present Focus hero card.
/// One band is active at any moment; bands roll forward across the day
/// and across the midnight boundary so the home screen always says
/// "this is what to think about in the present."
///
/// Boundaries are coarse on purpose — minute-precision would create a
/// jarring UX every time the band edge crossed mid-meal / mid-set.
/// Weekday vs weekend differs only for the mindful-eating bands; the
/// workout / evening / night bands are the same shape regardless.
enum TimeBand: String, CaseIterable {
    case morning      // weekday 06–12  : mindful eating + skincare AM
    case midday       // weekday 12–17  : mindful eating
    case workout      // 17–19          : train
    case reachOut     // 19–22          : connect + embodiment
    case night        // 22–06          : wind down

    /// Active band for the supplied date (defaults to now). Calls into
    /// `Calendar.current` so the user's locale + timezone are respected.
    static func current(at date: Date = Date()) -> TimeBand {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        switch hour {
        case 6..<12:  return .morning
        case 12..<17: return .midday
        case 17..<19: return .workout
        case 19..<22: return .reachOut
        default:      return .night
        }
    }

    /// Short uppercased label rendered in the band-tag pill.
    var tag: String {
        switch self {
        case .morning:  return "MORNING"
        case .midday:   return "MIDDAY"
        case .workout:  return "WORKOUT"
        case .reachOut: return "EVENING"
        case .night:    return "NIGHT"
        }
    }

    /// Big-print "what to think about right now" line. Imperative voice.
    var headline: String {
        switch self {
        case .morning:  return "Eat mindfully."
        case .midday:   return "Eat mindfully."
        case .workout:  return "Train."
        case .reachOut: return "Reach out. Be in your body."
        case .night:    return "Wind down."
        }
    }

    /// One-line subtitle clarifying the focus. Less imperative than the
    /// headline — meant to be read once and absorbed.
    var subtitle: String {
        switch self {
        case .morning:  return "Slow bites, attention on the food, no screens."
        case .midday:   return "Same again — taste, chew, notice."
        case .workout:  return "The prescribed session is waiting. Start when ready."
        case .reachOut: return "Send one message. Move your body — stretch, walk, breathe."
        case .night:    return "Phone away. Lights down. Tomorrow starts well-rested."
        }
    }

    /// Glyph for the hero card. SF Symbol names; cyan-tinted in-view.
    var symbol: String {
        switch self {
        case .morning:  return "fork.knife"
        case .midday:   return "fork.knife"
        case .workout:  return "figure.strengthtraining.traditional"
        case .reachOut: return "bubble.left.and.bubble.right"
        case .night:    return "moon.stars"
        }
    }

    /// Accent color for the hero card border + tag. Kept inside this
    /// type so callers don't need to maintain a parallel switch.
    var accent: Color {
        switch self {
        case .morning:  return .orange
        case .midday:   return .yellow
        case .workout:  return .cyan
        case .reachOut: return .indigo
        case .night:    return .purple
        }
    }

    /// The next band edge after `date` — used to schedule the rollover
    /// timer so the Now tab updates *exactly* on the boundary, not on
    /// the next foreground.
    static func nextEdge(after date: Date = Date()) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        // Order: 6, 12, 17, 19, 22, then 6 the following day.
        let edges = [6, 12, 17, 19, 22]
        for h in edges where h > hour {
            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour = h
            comps.minute = 0
            comps.second = 0
            if let edge = cal.date(from: comps), edge > date {
                return edge
            }
        }
        // Past 22 — next edge is tomorrow at 6am.
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = 6
        comps.minute = 0
        comps.second = 0
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.date(from: comps) ?? date) {
            return tomorrow
        }
        return date.addingTimeInterval(3600)
    }
}
