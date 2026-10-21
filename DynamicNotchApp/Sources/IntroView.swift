import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Intro card shown in the open notch on first launch.
//
// app review 2026-10-20: the card painted `nonShockingWhite` (0.92 white) while the
//   notch hierarchy is forced dark, so HelloView's `.primary` text was white-on-white; its
//   "Get Started" only advanced to a "Learn More" link to a placeholder domain, and the only way out
//   was an invisible whole-card tap. The card now renders its own content in the light scheme
//   (readable on the light card regardless of the notch's dark scheme), keeps clear of the camera
//   housing, and has explicit "Get Started" and close (✕) buttons that persist `SettingsStore[.intro]`.
//   The old HelloView was deleted 2026-10-20.
struct IntroView: View {
    @Environment(\.notchViewModel) private var notchViewModel
    @Environment(\.notchSize) private var notchSize

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                // hello.lottie (Lottie) → SF Symbol with a periodic wave
                IntroWaveSymbol()
                    .frame(maxHeight: 90)

                Text("Welcome to DynamicNotch!")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Button {
                    dismiss()
                } label: {
                    Text("Get Started")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, notchSize.height + 4)
            .padding(.bottom, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text("Close"))
            .accessibilityLabel(Text("Close"))
            .padding(.top, notchSize.height + 6)
            .padding(.trailing, 14)
        }
        .background {
            ZStack {
                Color.nonShockingWhite
            }
        }
        // the card is light: render controls/text for the light scheme (the notch forces .dark)
        .environment(\.colorScheme, .light)
        .frame(maxHeight: .infinity)
    }

    private func dismiss() {
        SettingsStore[.intro] = false
        withAnimation { notchViewModel?.showIntro = false }
    }
}


/// Intro animation: a waving hand that wiggles every couple of seconds, tinted with the accent colour.
/// Respects Reduce Motion (symbol effects are suppressed by the system).
struct IntroWaveSymbol: View {
    var body: some View {
        Image(systemName: "hand.wave.fill")
            .font(.system(size: 54, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.accentColor)
            .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 1.6)))
            .accessibilityHidden(true)
    }
}
