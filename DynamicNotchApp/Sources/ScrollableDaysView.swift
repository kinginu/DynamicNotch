import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

/// Horizontal day picker (originally: ScrollView(.horizontal) / LazyHStack of
/// CalendarDayView, 44 pt cells, edge fade mask).
///
/// A fixed 7-day strip that fits the calendar widget's width. The calendar widget changes
///   `weekStart` to page between weeks.
struct ScrollableDaysView: View {
    var weekStart: Date
    @Binding var selectedDate: Date
    /// Start-of-day dates that get an event dot.
    var eventDays: Set<Date> = []

    private let calendar: Calendar = .current

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                CalendarDayView(
                    date: day,
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                    isCurrentMonth: true,
                    hasEvents: eventDays.contains(calendar.startOfDay(for: day))
                )
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { selectedDate = day }
            }
        }
        .frame(height: 40)
    }
}
