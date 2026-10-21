import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Text editor that grows with its text between minHeight and maxHeight (measured with
//   NSString.boundingRect).
import SwiftUI
import AppKit

struct MultilineTextField: View {

    @Binding var text: String

    @FocusState var isFocused: Bool

    @State private var dynamicHeight: CGFloat = 30

    var minHeight: CGFloat = 30

    var maxHeight: CGFloat = 200

    var body: some View {
        TextEditor(text: $text)
            .focused($isFocused)
            .frame(width: dynamicHeight, alignment: .center)
            .onChange(of: text) { _ in
                recalculateHeight()
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: NotchHeightKey.self, value: geometry.size.height)
                }
            )
            .onPreferenceChange(NotchHeightKey.self) { height in
                dynamicHeight = height
            }
            .border(
                Color(red: 0.21, green: 0.23, blue: 0.4, opacity: 0.2),
                width: 3.0
            )
            .overlay(
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1))
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 3.0, style: .continuous)
            )
            .multilineTextAlignment(.center)
    }

    // Measures the text in the system font and clamps the height to [minHeight, maxHeight].
    func recalculateHeight() {
        let nsText = text as NSString

        let font = NSFont.systemFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: 1)
        let boundingRect = nsText.boundingRect(
            with: maxSize,
            options: .usesLineFragmentOrigin,
            attributes: attributes,
            context: nil
        )

        let computedHeight = boundingRect.height

        let clampedHeight = min(maxHeight, max(minHeight, computedHeight))

        dynamicHeight = clampedHeight
    }
}

// height reported by the editor's GeometryReader
struct NotchHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
