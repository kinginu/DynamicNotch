import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Complex Button with lock icon, Lottie animation
// lockedOrTyping Bool, NSColor RGB extraction for Lottie color value provider
// BindStatesStyle button style, onContinuousHover
// .onChange(of: lockedOrTyping)
struct LockedIndicatorView: View {
    @State private var lockedOrTyping: Bool = false

    var body: some View {
        Button(action: {
            lockedOrTyping.toggle()
        }) {
            Image(systemName: lockedOrTyping ? "lock.fill" : "lock.open")
                .font(.system(size: 12))
        }
        .buttonStyle(BindStatesStyle())
        .onContinuousHover { phase in

        }
        .onChange(of: lockedOrTyping) { newValue in

        }
    }
}