import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Combine
import SwiftUI

// View modifire that debounces onChange callbacks with a configurable
//   delay, avoiding rapid-fire updates on slider/text field changes.
struct DebouncedOnChangeModifier<Value: Equatable>: ViewModifier {

    // Value to observe for changes
    var value: Value

    // Debounce interval in seconds
    var debounceInterval: Double = 0.3

    // Action to perform after debounce
    var action: (Value) -> Void

    // Debounce subject
    @State private var subject = PassthroughSubject<Value, Never>()

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { newValue in
                subject.send(newValue)
            }
            .onReceive(
                subject
                    .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            ) { debouncedValue in
                action(debouncedValue)
            }
    }
}
