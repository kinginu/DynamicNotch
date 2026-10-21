import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import EventKit

// list of events
struct CalendarEventsView: View {
    var events: [EKEvent] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(events, id: \.eventIdentifier) { event in
                CalendarEventView(event: event)
            }
        }
    }
}
