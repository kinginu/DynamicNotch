import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import EventKit

// Calendar widget with selectable dates
//
// A month grid does not fit the ≈200 pt tall nook row, so the widget is a single row
//   of days above the selected day's events from CalendarManager (EventKit). Without calendar
//   access it shows a request / System Settings button.
// restyle (2026-10-20, Apple-native): abbreviated month name ("Oct", title3 bold)
//   beside a five-day strip. User report (2026-10-20, "the selected date should always be in the
//   centre; hard to tell which day is selected"): the strip is ALWAYS centred on the selected day.
//   Clicking a day, the ‹ › buttons, the "Today" chip and a horizontal drag all change the selected
//   day and the strip slides to re-centre on it (days are keyed by date in a 9-day row of which the
//   middle 5 are visible, so a 1–2 day move slides cells that already exist; the drag follows the
//   pointer live). The selected day is a filled accent circle (CalendarDayView), today when not
//   selected an accent ring. The caption row names the selected date ("Today · Tue, Oct 20" /
//   "Wed, Oct 21"), and the event list below shows that day's events, or "Nothing for today".
struct CalendarWidgetView: View {

    // Selected date
    @State private var _selectedDate: Date = Date()

    @State private var events: [EKEvent] = []

    /// Strip days that have events (dots under the dates).
    @State private var eventDays: Set<Date> = []

    /// Live horizontal drag of the day strip (points).
    @State private var dragOffset: CGFloat = 0

    private var manager: CalendarManager { CalendarManager.shared }

    // Calendar instance
    private let calendar = Calendar.current

    /// Days visible either side of the selected day (5 days fit the 220 pt cell).
    private static let visibleRadius = 2
    /// Days laid out either side of the selected day (the extra ones sit hidden beyond the clip
    /// edge so a re-centre by up to 2 days slides existing cells in instead of fading new ones).
    private static let stripRadius = 4
    private static let stripHeight: CGFloat = 46

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.spacing) {
            header
            dayCaption
            content
        }
        .nookWidgetFrame()
        .nookWidgetGalleryHook()
        .onAppear {
            manager.refreshAuthorizationStatus()
            reload()
        }
        .onChange(of: _selectedDate) { _, _ in reload() }
        // every coalesced refresh (edits, other days' changes, selection, access), not only a
        // change of today's event count
        .onChange(of: manager.revision) { _, _ in reload() }
        .onChange(of: manager.authorizationStatus) { _, _ in reload() }
    }

    // MARK: - selectedDate

    var selectedDate: Date {
        _selectedDate
    }

    // MARK: - Init

    // init()
    init() {}

    // MARK: - Parts

    private var selectedDay: Date { calendar.startOfDay(for: _selectedDate) }

    /// The laid-out strip: the selected day ± `stripRadius`, the selected day in the middle.
    private var stripDays: [Date] {
        (-Self.stripRadius...Self.stripRadius).compactMap { calendar.date(byAdding: .day, value: $0, to: selectedDay) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(monthTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 30, alignment: .leading)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
            dayStrip
        }
    }

    /// Five visible days centred on the selected one (see the header comment).
    private var dayStrip: some View {
        GeometryReader { geo in
            let visible = CGFloat(Self.visibleRadius * 2 + 1)
            let cell = geo.size.width / visible
            HStack(spacing: 0) {
                ForEach(stripDays, id: \.self) { day in
                    Button {
                        select(day)
                    } label: {
                        CalendarDayView(
                            date: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                            isCurrentMonth: true,
                            hasEvents: eventDays.contains(day)
                        )
                        .frame(width: cell, height: Self.stripHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // the middle cell (index stripRadius) sits in the middle of the visible width
            .offset(x: -CGFloat(Self.stripRadius - Self.visibleRadius) * cell + dragOffset)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in dragOffset = value.translation.width }
                    .onEnded { value in
                        let travel = value.predictedEndTranslation.width
                        let days = -Int((travel / cell).rounded())
                        let clamped = max(-7, min(7, days))
                        withAnimation(.snappy) {
                            dragOffset = 0
                            if clamped != 0, let day = calendar.date(byAdding: .day, value: clamped, to: selectedDay) {
                                select(day, animated: false)
                            }
                        }
                    }
            )
        }
        .frame(height: Self.stripHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing).frame(width: 6)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing).frame(width: 6)
            }
        }
    }

    /// The selected date ("Today · Tue, Oct 20" / "Tomorrow · Wed, Oct 21" / "Fri, Oct 24") with
    /// ‹ › day steppers, and a Today chip when another day is selected.
    private var dayCaption: some View {
        HStack(spacing: 2) {
            ViewThatFits(in: .horizontal) {
                captionText(relative: true)
                captionText(relative: false)
            }
            .contentTransition(.numericText())
            Spacer(minLength: 2)
            if !calendar.isDateInToday(_selectedDate) {
                NookChip(horizontalPadding: 6, action: { select(Date()) }) { Text("Today") }
                    .fixedSize()
                    .transition(.opacity)
            }
            stepButton(-1, systemImage: "chevron.left", label: Text("Previous Day"))
            stepButton(1, systemImage: "chevron.right", label: Text("Next Day"))
        }
        .frame(height: 22)
        .animation(.snappy, value: calendar.isDateInToday(_selectedDate))
    }

    private func captionText(relative: Bool) -> some View {
        Text(relative ? relativeDayTitle : dateTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(calendar.isDateInToday(_selectedDate) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .fixedSize()
    }

    private func stepButton(_ days: Int, systemImage: String, label: Text) -> some View {
        Button {
            if let day = calendar.date(byAdding: .day, value: days, to: selectedDay) { select(day) }
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private var content: some View {
        if !manager.hasReadAccess {
            accessView
        } else if events.isEmpty {
            NookWidgetPlaceholder(systemImage: "calendar",
                                  title: calendar.isDateInToday(_selectedDate) ? Text("Nothing for today") : Text("No events"))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(events, id: \.calendarItemIdentifier) { event in
                        CalendarWidgetEventRow(event: event)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var accessView: some View {
        if manager.authorizationStatus == .notDetermined {
            NookWidgetAccessState(title: Text("Show your events here"), actionTitle: "Allow Access", prominent: true) {
                Task { await manager.requestFullAccess(); reload() }
            }
        } else {
            NookWidgetAccessState(title: Text("No access to Calendar"), actionTitle: "Open System Settings", prominent: false) {
                Task { await manager.requestAccessFromUser() }
            }
        }
    }

    // MARK: - Helpers

    private var monthTitle: String {
        _selectedDate.formatted(.dateTime.month(.abbreviated))
    }

    /// "Tue, Oct 20" (localized).
    private var dateTitle: String {
        _selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Today · Tue, Oct 20" for today / tomorrow / yesterday, else the date alone.
    private var relativeDayTitle: String {
        let relative: String
        if calendar.isDateInToday(_selectedDate) { relative = String(localized: "Today") }
        else if calendar.isDateInTomorrow(_selectedDate) { relative = String(localized: "Tomorrow") }
        else if calendar.isDateInYesterday(_selectedDate) { relative = String(localized: "Yesterday") }
        else { return dateTitle }
        return relative + " · " + dateTitle
    }

    /// Selects a day; the strip re-centres on it (animated unless the caller animates).
    private func select(_ day: Date, animated: Bool = true) {
        let start = calendar.startOfDay(for: day)
        let apply = { _selectedDate = calendar.isDateInToday(start) ? Date() : start }
        if animated { withAnimation(.snappy) { apply() } } else { apply() }
    }

    private func reload() {
        let list = manager.events(on: _selectedDate)
        // compare what a row shows, so an edited time / title replaces the stale event objects
        if list.map(Self.rowSignature) != events.map(Self.rowSignature) {
            events = list
        }
        var days: Set<Date> = []
        for day in stripDays {
            if calendar.isDate(day, inSameDayAs: _selectedDate) {
                if !list.isEmpty { days.insert(day) }
            } else if !manager.events(on: day).isEmpty {
                days.insert(day)
            }
        }
        if days != eventDays { eventDays = days }
    }

    /// What an event row depends on (identity, edit stamp, times, title, calendar colour).
    private static func rowSignature(_ event: EKEvent) -> String {
        [event.calendarItemIdentifier,
         "\(event.lastModifiedDate?.timeIntervalSinceReferenceDate ?? 0)",
         "\(event.startDate?.timeIntervalSinceReferenceDate ?? 0)",
         "\(event.endDate?.timeIntervalSinceReferenceDate ?? 0)",
         "\(event.isAllDay)",
         event.title ?? "",
         event.calendar?.calendarIdentifier ?? ""].joined(separator: "\u{1F}")
    }

    static func startOfWeek(for date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
        return start ?? calendar.startOfDay(for: date)
    }
}

/// One event row: calendar colour bar, title, time (or "All day").
private struct CalendarWidgetEventRow: View {
    let event: EKEvent

    private var timeText: String {
        if event.isAllDay { return String(localized: "All day") }
        guard let start = event.startDate else { return "" }
        let startText = start.formatted(date: .omitted, time: .shortened)
        if let end = event.endDate {
            return "\(startText) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return startText
    }

    private var isPast: Bool {
        (event.endDate ?? .distantFuture) < Date()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Capsule()
                .fill(Color(cgColor: event.calendar?.cgColor ?? NSColor.systemBlue.cgColor))
                .frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius)
        .opacity(isPast ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}
