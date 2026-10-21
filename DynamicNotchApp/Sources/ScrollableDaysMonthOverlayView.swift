import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

/// A tappable month-name overlay rendered as a Button.
///
///   2. ButtonStyle = ShrinkOnClick
///   3. Label = VStack { Text(monthName) }.padding.contentShape(Rectangle()).foregroundStyle(Color)
struct ScrollableDaysMonthOverlayView: Equatable, View {
    var action: () -> Void

    // Month name string displayed inside the button label Text
    var monthName: String = ""

    // Button with ShrinkOnClick style
    // Button label: VStack with Text, padding, contentShape, foregroundStyle
    var body: some View {
        Button(action: action) {
            VStack {
                Text(monthName)
            }
            .padding()  // padding on VStack
            .contentShape(Rectangle())  // contentShape(Rectangle())
            .foregroundStyle(Color.primary)  // foregroundStyle(Color)
            .opacity(0.6)
        }
        .buttonStyle(ShrinkOnClick())  // ShrinkOnClick button style
        .frame(maxWidth: .infinity)
    }

    // Equatable conformance
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.monthName == rhs.monthName
    }

}