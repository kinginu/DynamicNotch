import SwiftUI
import EventKit

/// Requests `.calendar` from `minutesBefore` before a timed event until 5 minutes after its start
/// (Settings ▸ Live Activities ▸ Calendar). Reads `CalendarManager.shared.events` and re-evaluates
/// every 30 s (a no-op while calendar access is not granted).
@MainActor @Observable
final class CalendarActivityMonitor {
    struct UpcomingEvent: Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var color: Color
    }

    /// Event shown by the `.calendar` activity.
    private(set) var upcomingEvent: UpcomingEvent? = nil

    @ObservationIgnored private weak var center: LiveActivityCenter?
    @ObservationIgnored private var timer: Timer? = nil

    private var manager: ActiveLiveActivitiesManager { .shared }

    func start(center: LiveActivityCenter) {
        self.center = center
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    func evaluate() {
        guard let settings = center?.calendarSettings, settings.isEnabled,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            setUpcomingEvent(nil)
            return
        }
        let now = Date()
        let lead = TimeInterval(max(0, settings.minutesBefore) * 60)
        let candidates = CalendarManager.shared.events.compactMap { event -> UpcomingEvent? in
            guard !event.isAllDay, let start = event.startDate, let end = event.endDate else { return nil }
            let hideAfter = min(end, start.addingTimeInterval(5 * 60))
            guard start.timeIntervalSince(now) <= lead, now < hideAfter else { return nil }
            return UpcomingEvent(
                id: event.eventIdentifier ?? "\(event.title ?? "")@\(start.timeIntervalSince1970)",
                title: event.title ?? "",
                start: start,
                end: end,
                color: event.calendar.map { Color(nsColor: $0.color) } ?? .blue
            )
        }
        var next = candidates.min { $0.start < $1.start }
        if settings.appearanceMode == .periodic, let event = next {
            // periodic: visible during the first minute of every 5-minute step before the start,
            // and for the minute around the start itself
            let minutesLeft = Int(ceil(event.start.timeIntervalSince(now) / 60))
            if minutesLeft > 0, minutesLeft % 5 != 0 { next = nil }
        }
        setUpcomingEvent(next)
    }

    private func setUpcomingEvent(_ event: UpcomingEvent?) {
        if event != upcomingEvent { upcomingEvent = event }
        if event != nil { manager.insertSync(.calendar) } else { manager.removeSync(.calendar) }
    }

    /// DEBUG `la:calendar`: a placeholder event so the forced activity has something to show.
    func debugEnsureEvent() {
        guard upcomingEvent == nil else { return }
        upcomingEvent = UpcomingEvent(id: "debug", title: "Debug event", start: Date().addingTimeInterval(300),
                                      end: Date().addingTimeInterval(3600), color: .blue)
    }
}

/// One side of the calendar activity: calendar symbol in the event's colour | minutes until start.
struct CalendarLiveActivityView: View {
    var side: LiveActivityView.ActivitySide
    var event: CalendarActivityMonitor.UpcomingEvent?

    var body: some View {
        switch side {
        case .leading:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(event?.color ?? .blue)
        case .trailing:
            if let event {
                TimelineView(.everyMinute) { context in
                    Text(verbatim: Self.minutesText(until: event.start, now: context.date))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(event.color)
                        .lineLimit(1)
                        .fixedSize()
                }
                .help(event.title)
            }
        }
    }

    /// "12m" before the start, "Now" once it started.
    static func minutesText(until start: Date, now: Date) -> String {
        let minutes = Int(ceil(start.timeIntervalSince(now) / 60))
        if minutes <= 0 { return String(localized: "Now") }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }
}
