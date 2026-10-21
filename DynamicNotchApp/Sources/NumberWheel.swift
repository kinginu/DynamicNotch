import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Used in TimerCreatorView context for scrolling hour/minute/second selection
import SwiftUI

// MARK: - NumberWheel

// Scrolling number picker with jiggle animation and visual feedback
// Range is 0..<60 for minutes/seconds or 0..<24 for hours
struct NumberWheel: View {

    @Binding var value: Int

    // @State var isJiggling: Bool — controls jiggle animation on selection
    @State private var isJiggling: Bool = false

    // The max value for the wheel range (60 for min/sec, 24 for hours)
    var range: Range<Int>

    // MARK: - Body

    //   VStack with ForEach over range, each row is rowLabel(index),
    //   scrollTargetLayout enabled, .onTapGesture to set value
    // ScrollView + LazyVStack or plain VStack wrapping ForEach
    var body: some View {
        VStack(spacing: 0) {
            ForEach(range, id: \.self) { index in
                rowLabel(index)
                    .onTapGesture {
                        value = index
                        focusWheel()
                    }
            }
        }
        .scrollTargetLayout()
    }

    // MARK: - Row Label

    //   Text("\(index)") with easeOut animation (0.3s),
    //   blur/scale visual effects based on isJiggling,
    //   offset based on distance from current value
    // Distance-based offset creates a physical "wheel" feel
    func rowLabel(_ index: Int) -> some View {
        Text("\(index)")
            .font(.system(size: 18, weight: .medium, design: .monospaced))
            .foregroundStyle(index == value ? Color.primary : Color.secondary)
            //   isJiggling ? 1.0 : 0 — 1.0 px blur when jiggling
            .blur(radius: isJiggling ? 1.0 : 0)
            //   isJiggling ? 0.95 : 1.0
            .scaleEffect(isJiggling ? 0.95 : 1.0, anchor: .center)
            //   Closer items are more centered, farther items offset for wheel illusion
            //   Ghost: offset = fabs(index - value) creates visual stagger
            .offset(y: CGFloat(index - value) * (isJiggling ? 1.5 : 0))
            //   Matches the wheel settle time
            .animation(.easeOut(duration: 0.3), value: value)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isJiggling)
            // Frame sizing to ensure consistent tap targets
            .frame(height: 28)
    }

    // MARK: - Focus Wheel

    //   Sets isJiggling = true, dispatch asyncAfter 0.1s to reset
    // The brief jiggle provides haptic-like visual feedback on selection
    func focusWheel() {
        isJiggling = true

        //   Resets isJiggling to false after a brief jiggle pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isJiggling = false
        }
    }
}
