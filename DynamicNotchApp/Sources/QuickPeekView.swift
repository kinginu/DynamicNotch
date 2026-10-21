import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   VStack (_VariadicViewO4Tree with VStackLayout)
//     → HStack
//           Image (opacity: 0.6 + font(.title) + foregroundStyle: Color.nonShockingWhite),
//           Text (fixedSize + alignment)
//         )
//       → opacity(0.5)
//       → padding(.all, top: 7.0, rest: 3.0)
//     → frame(maxWidth: .infinity, alignment: .leading)
//     → background(Color.nonShockingWhite.opacity(0.1))
//
// Constants:
//   Padding top: 7.0, leading/bottom/trailing: 3.0
//   Background opacity: 0.1
//

import SwiftUI

//   A single quick peek item showing an icon and title with subdued styling.
struct QuickPeekView: View {

    // The quick peek data from DynamicNotchState
    var quickPeek: DynamicNotchState.QuickPeek                     // data model

    // MARK: - body

    var body: some View {
        // Root: VStack (_VariadicViewO4Tree with VStackLayout)
        VStack {
            HStack {
                // Image: opacity 0.6 + font(.title) + foregroundStyle(nonShockingWhite)
                Image(systemName: quickPeek.name)                // systemName from QuickPeek.name
                    .opacity(0.6)
                    .font(.title)
                    .foregroundStyle(                             // foregroundStyle
                        Color.nonShockingWhite                   
                    )

                // Text with fixedSize + alignment
                Text(quickPeek.title ?? quickPeek.name)          // title, fallback to name
                    .fixedSize()                                  // fixedSize layout
                    .multilineTextAlignment(.leading)
            }
            .opacity(0.5)

            // padding(.all, top: 7.0, rest: 3.0)
            .padding(EdgeInsets(                                   // EdgeO3Set ≡ EdgeInsets
                top: 7.0,                                       // top: 7.0
                leading: 3.0,                                    // leading: 3.0
                bottom: 3.0,                                    // bottom: 3.0
                trailing: 3.0                                    // trailing: 3.0
            ))
        }
        // frame: maxWidth .infinity, alignment .leading
        .frame(
            maxWidth: .infinity,                                 // maxWidth .infinity
            alignment: .leading                                  // alignment .leading
        )

        // background: Color.nonShockingWhite.opacity(0.1)
        .background(                                              // background modifier
            Color.nonShockingWhite                                // Color.nonShockingWhite
                .opacity(0.1)                                    // 0.1 opacity
        )
    }
}