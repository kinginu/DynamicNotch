import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Image(systemName:) with font(.system(size:0, design:.default))
// foregroundStyle(.blue), frame(28, 28), padding(.all, 0)
// background(Circle().fill(selected/nonShockingWhite alternate))
// overlay HStack(CircleButton?, Spacer), padding, hoverRegion
// scaleTransition(anchor: .bottomTrailing), matchedGeometry("note-icon")
// opacity(hover?), transition(.scaleAndBlur)
struct NoteIconView: View {
    let note: NoteDocument?
    @State private var isHovering: Bool = false
    @Namespace private var animation

    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: 0, weight: .semibold, design: .default))
            .foregroundStyle(.blue)
            .frame(width: 28, height: 28)
            .padding(.all, 0)
            .background(
                Circle()
                    .fill(isHovering ? Color.nonShockingWhite : Color.selected)
            )
            .overlay(alignment: .center) {
                HStack {
                    if isHovering {
                        CircleButton(action: {})
                    }
                    Spacer()
                }
                .padding(.all, 4)
            }
            .opacity(isHovering ? 1.0 : 0.87)
            .scaleEffect(isHovering ? 1.0 : 0.95, anchor: .bottomTrailing)
            .matchedGeometryEffect(id: "note-icon", in: animation)
            .onContinuousHover { phase in
                withAnimation(.easeOut(duration: 0.15)) {
                    if case .active = phase { isHovering = true } else { isHovering = false }  // HoverPhase is not Equatable
                }
            }
    }
}