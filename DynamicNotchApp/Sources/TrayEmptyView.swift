import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

//   Image + Text, nonShockingWhite foreground, opacity, scaleAndBlur transition).
struct TrayEmptyView: View {
    var body: some View {
        // restyle (2026-10-20): tray.and.arrow.down (hierarchical) + subheadline, secondary.
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.title.weight(.regular))
                .symbolRenderingMode(.hierarchical)
            Text("Drop files here")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .transition(.scaleAndBlur)
    }
}
