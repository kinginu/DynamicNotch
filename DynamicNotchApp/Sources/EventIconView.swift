import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI
import Foundation

struct EventIconView: View {
    @Environment(\.date) private var date: Date

    @Environment(\.dynamicNotchState) private var notchState: DynamicNotchState?  // env key is optional

    var eventDate: Date

    var body: some View {
        let iconName: String = date < eventDate ? "calendar" : ""

        Image(systemName: iconName)
            .font(.system(size: 11))
            .foregroundColor(.blue)
            .padding(.top, 0)
            .quickPeekScaling(
                scaling: isFirstQuickPeekTopLeading,
                anchor: firstQuickPeekAnchor,
                max: 1.2
            )
            .allowsHitTesting(false)
            .frame(
                minWidth: 0,
                idealWidth: .infinity,
                maxWidth: .infinity,
                minHeight: nil,
                idealHeight: nil,
                maxHeight: nil,
                alignment: .center
            )
            .onHover { isHovering in
                if isHovering {
                    notchState?.quickPeeks = quickPeeks
                } else {
                    notchState?.quickPeeks = nil
                }
            }
    }

    private var isFirstQuickPeekTopLeading: Bool {
        guard let first = quickPeeks.first else { return false }
        return first.anchor == .topLeading
    }

    private var firstQuickPeekAnchor: UnitPoint {
        quickPeeks.first?.anchor ?? .topLeading
    }

    var quickPeeks: [DynamicNotchState.QuickPeek] {
        let firstFormatted = eventDate.formatted(
            date: .omitted,
            time: .shortened
        )
        let secondFormatted = eventDate.formatted(
            date: .omitted,
            time: .shortened
        )

        return [
            DynamicNotchState.QuickPeek(
                id: UUID(),
                title: firstFormatted,
                name: "calendar",
                color: nil,
                anchor: .topLeading
            ),
            DynamicNotchState.QuickPeek(
                id: UUID(),
                title: firstFormatted + " - " + secondFormatted,
                name: "clock",
                color: nil,
                anchor: .topLeading
            )
        ]
    }
}
