import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// VStack with Image(font) + Text, flexFrame maxWidth .infinity
// background InsettableBackgroundShape Color.selected RoundedRectangle radi 13
// foregroundStyle(.nonShockingWhite)
// overlay HStack(CircleButton? + Spacer) with padding
// hoverRegion with State<Bool> for drag hover state
struct ReorderWidgetDragView: View {
    @State private var isHovering: Bool = false

    var body: some View {
        VStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16))
            Text("Drag to reorder")
        }
        .frame(maxWidth: .infinity) // flexFrame → frame
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.selected)
        )
        .foregroundStyle(Color.nonShockingWhite)
        .overlay(alignment: .center) {
            HStack {
                if isHovering {
                    CircleButton(action: {})
                }
                Spacer()
            }
            .padding(.all, 6)
        }
        .onContinuousHover { phase in
            withAnimation(.easeOut(duration: 0.15)) {
                if case .active = phase { isHovering = true } else { isHovering = false } // HoverPhase isn't Equatable
            }
        }
    }
}