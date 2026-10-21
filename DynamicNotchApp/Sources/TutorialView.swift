import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Tutorial: a row of TutorialItemViews, centred, shown with the scale-and-blur transition.

struct TutorialView: View {

    var body: some View {
        VStack {
            HStack {
                TutorialItemView()  // multiple items
                TutorialItemView()
            }
            // NavigationLink / Link for getting started
            HStack {
                Button {
                    // dismiss action
                } label: {
                    Label {
                        Text("Get Started")  // localized
                    } icon: {
                        Image(systemName: "arrow.forward")
                    }
                }
                .buttonStyle(.plain)  // _PlainButtonStyle
                .foregroundStyle(HierarchicalShapeStyle.secondary)  // _HierarchicalShapeStyle .hierarchical is not a ShapeStyle member
            }
            // Conditional content for different tutorial states
        }
        .environment(\.multilineTextAlignment, .center)

        .frame(minWidth: nil, idealWidth: 20.0, maxWidth: nil,
               minHeight: nil, idealHeight: nil, maxHeight: nil,
               alignment: .center)

        .padding(16.0)

        .transition(.scaleAndBlur) // shared AnyTransition.scaleAndBlur takes no parameters (anchor .top, blur 30)
    }
}