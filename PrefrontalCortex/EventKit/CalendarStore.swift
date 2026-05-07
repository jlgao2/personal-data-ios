import Foundation
import EventKit

/// Thin EventKit wrapper. Reads upcoming events (live, on-device — no
/// dependency on the bundle's Google Calendar feed). Optionally writes
/// reminders for goals and reach-out check-ins.
@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    private let store = EKEventStore()

    @Published var authorized: Bool = false
    @Published var upcoming: [LiveCalendarEvent] = []
    @Published var lastError: String?

    /// iOS 17+: requestFullAccessToEvents. Older versions fall through to
    /// the legacy method.
    func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                authorized = try await store.requestFullAccessToEvents()
            } else {
                authorized = try await withCheckedThrowingContinuation { cont in
                    store.requestAccess(to: .event) { granted, error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume(returning: granted) }
                    }
                }
            }
        } catch {
            lastError = "Calendar access denied: \(error.localizedDescription)"
            authorized = false
        }
    }

    /// Load the next `days` worth of events into `upcoming`.
    func loadUpcoming(days: Int = 14) async {
        guard authorized else { return }
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(days * 86_400))
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        upcoming = events.map { e in
            LiveCalendarEvent(
                id: e.eventIdentifier ?? UUID().uuidString,
                summary: e.title ?? "(no title)",
                start: e.startDate,
                end: e.endDate,
                isAllDay: e.isAllDay,
                location: e.location,
                calendarTitle: e.calendar?.title
            )
        }
    }

    /// Create a calendar event. Used by Goal "Add reminder" + Reach Out
    /// "Schedule check-in" buttons.
    func createEvent(title: String,
                     date: Date,
                     duration: TimeInterval = 30 * 60,
                     notes: String? = nil) async -> Bool {
        guard authorized else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(duration)
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }
}

struct LiveCalendarEvent: Identifiable {
    let id: String
    let summary: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendarTitle: String?
}
