import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Generic picker item row for multiple selection settings
struct MultipleSettingsPickerItemView<Element: Hashable>: View {

    // The element this row represents
    let element: Element

    // Whether this element is currently selected
    let selected: Bool

    // Selection action callback
    let select: (Element) -> Void

    // Whether this row is disabled
    let disabled: Bool

    // Toggle binding (e.g., for bluetooth)
    @Binding var isOn: Bool

    // MARK: - Body

    // Renders a togglable row with checkmark indicator
    var body: some View {
        Button {
            if !disabled {
                select(element)
            }
        } label: {
            HStack {
                // Label text derived from element description
                Text(String(describing: element))
                    .foregroundStyle(disabled ? .secondary : .primary)

                Spacer()

                // Checkmark when selected
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - isOn

    var isOnComputed: Bool {
        selected
    }

    // MARK: - Init

    // init(element:selected:select:disabled:isOn:)
    init(element: Element, selected: Bool, select: @escaping (Element) -> Void, disabled: Bool, isOn: Binding<Bool>) {
        self.element = element
        self.selected = selected
        self.select = select
        self.disabled = disabled
        self._isOn = isOn
    }

    // MARK: - handleBluetoothToggle

    // Handles bluetooth permission toggling
    func handleBluetoothToggle() {
        guard !disabled else { return }
        select(element)
    }
}