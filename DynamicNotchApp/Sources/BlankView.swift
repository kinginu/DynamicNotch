import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

struct BlankView: View {
    var body: some View {
        VStack(alignment: .center) {
            Image(systemName: "questionmark")
                .font(nil as Font?)

            Text("")
        }
        .foregroundStyle(HierarchicalShapeStyle.primary)
    }
}
