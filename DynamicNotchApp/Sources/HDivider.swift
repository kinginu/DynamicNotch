import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// horizontal counterpart of VDivider: invisible 1pt-high flexible-width spacer
struct HDivider: View {
    var body: some View {
        Color.clear
            .opacity(0)
            .frame(minWidth: 0, idealWidth: 1.0, maxWidth: .infinity,
                   minHeight: 0, idealHeight: 1, maxHeight: nil,
                   alignment: .center)
            .allowsHitTesting(false)
    }
}
