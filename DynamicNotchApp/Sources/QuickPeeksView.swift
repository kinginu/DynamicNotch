import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   HStack
//     ForEach(quickPeeks)
//       TheMarquee with parameters:
//         secsBeforeLooping, speedPtsPerSec, marqueeAlignment(.leading),
//         nonMovingAlignment(.center), horizontalPadding, fadeLength
//     _ConditionalContent: if any peek → HStack; else EmptyView
//
// frame(height: envWidth + 70.0) from environment size check
//

import SwiftUI

//   Horizontal scrolling marquee of quick peek items.
struct QuickPeeksView: View {

    // Quick peeks array from DynamicNotchState
    var quickPeeks: [DynamicNotchState.QuickPeek]                   // data source

    // Environment size for frame calculation
    @Environment(\.displaySize) private var displaySize            // env size check

    // MARK: - body

    var body: some View {
        //   If quick peeks non-empty → HStack with TheMarquee
        //   Else → EmptyView
        if quickPeeks.isEmpty {                                   // _ConditionalContent
            // EmptyView branch
            EmptyView()                                           // fallback
        } else {
            // HStack with ForEach
            HStack(alignment: .center) {                          // HStack layout

                ForEach(quickPeeks) { peek in                     // ForEach pattern

                    // TheMarquee here takes only `content: () -> AnyView`
                    TheMarquee {
                        // Content for each peek inside TheMarquee
                        AnyView(QuickPeekView(quickPeek: peek))    // single peek view
                    }
                }
            }
            .frame(height: displaySize.width + 70.0)           // envWidth + 70.0
        }
    }
}