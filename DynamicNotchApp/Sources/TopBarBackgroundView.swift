import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Group with ConditionalContent(ArrowForPanningView / EmptyView)
// flexFrame with maxWidth .infinity alignment center
// Conditional: if leading → scaleAndBlur(anchor: .leading, blur: 30)
//   else → scaleAndBlur(anchor: .trailing, blur: 30)
// TransactionKey for transition key
struct TopBarBackgroundView: View {
    // defaults so TopBarView can construct it without arguments
    var isLeading: Bool = true
    var onClose: () -> Void = {}

    var body: some View {
        Group {
            if isLeading {
                ArrowForPanningView()
                    .flexFrame(maxWidth: .infinity, alignment: .center)
            } else {
                EmptyView()
            }
        }
        // AnyTransition.scaleAndBlur takes no anchor/blur parameters
        .transition(.scaleAndBlur)
    }
}