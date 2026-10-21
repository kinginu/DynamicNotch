import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// NookView is the main container for the Notch/Nook widget area.
// NotchView draws TopBarView in the notch-height row and dispatches tray mode itself, and the liquid-glass
//   background is drawn by NotchView. NookView only hosts the widget row
//   (Support/NookWidgetGrid.swift).
struct NookView: View {
    var body: some View {
        NookWidgetGrid()
    }
}
