import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Bridges ScrollWheelNSView's callbacks to SwiftUI
struct ScrollWheelViewRepresentable: NSViewRepresentable {
    var onDragChanged: ((CGSize, CGPoint, CGSize) -> Void)? = nil
    var onDragEnded: ((CGSize, CGPoint, CGSize) -> Void)? = nil
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> ScrollWheelNSView {
        ScrollWheelNSView(frame: .zero)
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onClick = onClick
    }
}