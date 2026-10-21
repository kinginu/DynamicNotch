import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI
import EventKit

// MARK: - CalendarEventView

struct CalendarEventView: View {

    // MARK: - Stored properties

    let event: EKEvent

    // Meeting detected from event, displayed as optional meeting button
    @State private var meeting: Meeting? = nil

    // Track hover state for onHover modifier in body
    @State private var isHovering: Bool = false

    // MARK: - meetingButtonBackground

    //   true:  Color.clear → background(LiquidGlassBackdrop(aspect:.timer, cornerRadius:998))
    //   false: Capsule() → fill(Material.bar) → shadow(color:Color(sRGBLinear,white:0.32))
    @Environment(\.generalSettings) private var generalSettings

    @ViewBuilder  // if/else of different view types
    var meetingButtonBackground: some View {
        if generalSettings.liquidGlassEnabled {
            Color.clear
                .background(alignment: .center) {
                    // LiquidGlassBackdrop takes no aspect / corner radius: clip it to a capsule
                    LiquidGlassBackdrop()
                        .clipShape(Capsule())
                }
        } else {
            Capsule()
                .fill(Material.bar)
                .shadow(
                    color: Color(.sRGBLinear, white: 0.32, opacity: 1.0),
                    radius: 0, x: 0, y: 0
                )
        }
    }

    // MARK: - timeDisplay

    // Time label:
    //   1. isMultiDay? → Date.FormatStyle.dateTime.day(.defaultDigits).month(.abbreviated) → formatted
    //   2. isAllDay? → LocalizedStringKey("All day")
    //   3. else: NSDateFormatter(dateStyle:none,timeStyle:short) + "j" template for locale-aware time
    //      → format start + end → LocalizedStringKey interpolation "start \u{2013} end"
    var timeDisplay: Text {
        if event.isMultiDay {
            let style = Date.FormatStyle.dateTime
                .day(.defaultDigits)
                .month(.abbreviated)
            return Text(verbatim: event.startDate.formatted(style))
        }

        if event.isAllDay {
            return Text(LocalizedStringKey("All day"))
        }

        let startDate = event.startDate
        let endDate = event.endDate

        //   Creates NSDateFormatter, dateStyle:none, timeStyle:short
        //   Gets template "j" → dateFormat from "dateFormatFromTemplate:options:locale:"
        //   If result contains "a" (AM/PM) → setDateFormat("h:mm a") → lowercased
        //   If result nil → raw stringFromDate
        func formatTime(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short

            if let templateResult = DateFormatter.dateFormat(
                fromTemplate: "j", options: 0, locale: .current
            ) {
                if templateResult.contains("a") {
                    formatter.dateFormat = "h:mm a"
                    return formatter.string(from: date).lowercased()
                }
            }
            return formatter.string(from: date)
        }

        let startStr = formatTime(startDate ?? Date())  // unwrap EKEvent dates
        let endStr = formatTime(endDate ?? Date())

        // built with a string interpolation literal instead of manual StringInterpolation calls
        let key: LocalizedStringKey = "\(startStr) \u{2013} \(endStr)"
        return Text(key, tableName: nil, bundle: nil, comment: nil)
    }

    // MARK: - meetingButton(for:)

    func meetingButton(for meeting: Meeting) -> some View {
        Button {
            openMeetingURL(meeting.url)
        } label: {
            Label {
                Text(meeting.service.localizedName)
            } icon: {
                Image(systemName: meeting.service.systemImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
            .padding(6)
            .background(alignment: .center) {
                meetingButtonBackground
            }
            .font(.body)
        }
        .buttonStyle(ShrinkOnClick())
    }

    // Opens meeting url using environment OpenURLAction
    @Environment(\.openURL) private var openURL
    @MainActor private func openMeetingURL(_ url: URL) {
        openURL(url)
    }

    // MARK: - openCalendarEvent

    func openCalendarEvent() {
        if let identifier = event.eventIdentifier,
           let url = URL(string: "ical://event/\(identifier)") {
            openURL(url)
        } else if let url = URL(string: "ical://") {
            openURL(url)
        }
    }

    // MARK: - body

    //     timeDisplay
    //       .multilineTextAlignment(.center)
    //       .padding([.top,.bottom], 6)
    //       .font(.caption2)
    //       .onHover(Bool)
    //       .overlay(alignment:.top) {
    //         VStack(spacing:0) {
    //           Color.nonShockingWhite.frame(w:32,h:1)  // divider
    //           if meeting != nil { meetingButton }
    //         }
    //       }
    //       .onTapGesture { openCalendarEvent() }
    //   }
    //   .fixedSize(horizontal:false, vertical:true)
    //   .foregroundStyle(.nonShockingWhite)
    //   .onAppear { meeting = detectMeetings(in:event) }
    //   .offset(y:3.5)
    //   .opacity(isHovering ? 1.0 : 0.3)
    var body: some View {
        VStack(alignment: .center) {  // .top is not a HorizontalAlignment
            timeDisplay
                .multilineTextAlignment(.center)
                .padding([.top, .bottom], 6)
                .font(.caption2)
                .onHover { hovering in
                    isHovering = hovering
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.nonShockingWhite
                            .frame(width: 32, height: 1)

                        if let meeting = meeting {
                            meetingButton(for: meeting)
                        }
                    }
                }
                .onTapGesture {
                    openCalendarEvent()
                }
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.nonShockingWhite)
        .onAppear {
            meeting = detectMeetings(in: event)
        }
        .offset(y: 3.5)
        .opacity(isHovering ? 1.0 : 0.3)
    }
}
