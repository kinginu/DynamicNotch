import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct CircleButton: View {
    // call sites use CircleButton() and CircleButton(action:)
    var action: () -> Void = {}

    // renamed from circleBackground (clashed with the view property)
    @State private var isHovering: Bool = false

    @ViewBuilder
    var circleBackground: some View {
        if isHovering {
            // GlassAspect has no .timerBlurred case; .subtleBlur used instead
            Color.clear
                .liquidGlass(
                    .subtleBlur,
                    cornerRadius: 13.5,
                    radiusProvider: nil,
                    slabsProvider: nil,
                    fallback: AnyView(
                        Color.clear
                            .background(
                                LiquidGlassBackdrop(),
                                alignment: .center
                            )
                    )
                )
        } else {
            Color.clear
                .opacity(0.2)
        }
    }

    var body: some View {
        Circle()
            .fill(Color.clear)
            .contentShape(Circle(), eoFill: true)
            .background(alignment: .center) {
                circleBackground
            }
            .frame(width: 32, height: 32)
            .onTapGesture { action() }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
    }
}
