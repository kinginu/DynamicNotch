import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Single day cell in calendar widget with selection highlight
struct CalendarDayView: Equatable, View {

    // The date this cell represents
    var date: Date

    // Whether this date is the currently selected date
    var isSelected: Bool = false

    // Whether this date belongs to the current displayed month
    var isCurrentMonth: Bool = true

    // event dot under the number
    var hasEvents: Bool = false

    // Calendar for date formatting
    private let calendar = Calendar.current

    // MARK: - Body

    // VStack with weekday name, day number with selection circle
    // restyle (2026-10-20, user report "hard to tell which day is selected"):
    //   selected day = filled accent circle with white bold text (the widget keeps it in the centre
    //   of the strip); today, when not selected = accent ring and accent text; weekday initial
    //   (caption2) over the date, a dot under days with events.
    var body: some View {
        let isToday = calendar.isDateInToday(date)
        VStack(spacing: 2) {
            weekDayNameView
                .foregroundStyle(weekdayStyle(isToday: isToday))

            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline.weight(isToday || isSelected ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(numberStyle(isToday: isToday))
                .frame(width: 26, height: 26)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }

            Circle()
                .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 3, height: 3)
                .opacity(hasEvents ? 1 : 0)
        }
        .opacity(isCurrentMonth ? 1.0 : 0.35)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date.formatted(date: .complete, time: .omitted)))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - weekDayNameView

    var weekDayNameView: some View {
        let dayText = calendar.veryShortWeekdaySymbols[
            calendar.component(.weekday, from: date) - 1
        ]

        return Text(dayText)
            .font(.caption2.weight(.semibold))
    }

    // Weekend days get a subtle pink tint, today the accent colour
    // selected = white on the accent circle, today = accent, weekends secondary
    private func numberStyle(isToday: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.white) }
        if isToday { return AnyShapeStyle(Color.accentColor) }
        if calendar.isDateInWeekend(date) { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    private func weekdayStyle(isToday: Bool) -> AnyShapeStyle {
        if isToday { return AnyShapeStyle(Color.accentColor) }
        if isSelected { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(.secondary)
    }
}
