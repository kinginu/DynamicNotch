import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct BluetoothDeviceIconView: View {
    @State private var systemName: String = "questionmark"

    var body: some View {
        Image(systemName: systemName)
            .resizable(capInsets: EdgeInsets(), resizingMode: .stretch)
            .aspectRatio(contentMode: .fill)
            .padding(.all, 0)
            .shadow(color: .white.opacity(0.3), radius: 0, x: 0, y: 0)
            .foregroundStyle(.white)
            .overlay(
                GeometryReader { geometry in
                    VStack {
                        BrightnessIndicatorValueView(brightness: 1.0, glowThreshold: 0) // fixed preview values
                            .frame(height: nil as CGFloat?)
                        BrightnessIndicatorCometView()
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.25)) {
                }
            }
    }
}
