import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI

// View displaying the remaining time for a timer widget.
//   Formats the time interval as an hours:minutes:seconds string.
struct TimeLeftView: View {

    // Target end date
    var targetDate: Date

    // Whether to show seconds
    var showSeconds: Bool = true

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            let remaining = max(0, targetDate.timeIntervalSince(Date()))
            let hours = Int(remaining) / 3600
            let minutes = Int(remaining) / 60 % 60
            let seconds = Int(remaining) % 60

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%02d", hours))
                    .font(.system(size: 24, weight: .medium).monospacedDigit())  // SwiftUI equivalent

                Text(":")
                    .font(.system(size: 24, weight: .light))

                Text(String(format: "%02d", minutes))
                    .font(.system(size: 24, weight: .medium).monospacedDigit())  // SwiftUI equivalent

                if showSeconds {
                    Text(":")
                        .font(.system(size: 24, weight: .light))

                    Text(String(format: "%02d", seconds))
                        .font(.system(size: 24, weight: .medium).monospacedDigit())  // SwiftUI equivalent
                }
            }
            .foregroundStyle(.primary)
        }
    }
}
