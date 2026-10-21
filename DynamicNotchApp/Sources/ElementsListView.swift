import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Generic list view for selecting elements with active tracking
struct ElementsListView<Element: Hashable>: View {

    // Available elements
    private let elements: [Element]

    // Selection callback
    private let selectElement: (Element) -> Void

    // Optional item disabler
    private let disableItem: ((Element) -> Bool)?

    // Currently selected element binding
    @Binding private var selectedElement: Element

    // Active (enabled/in-use) elements binding
    @Binding private var activeElements: [Element]

    // MARK: - Body

    // List with checkmarks for active elements
    var body: some View {
        List(elements, id: \.self) { element in
            MultipleSettingsPickerItemView(
                element: element,
                selected: isSelected(element),
                select: { selectElement($0) },
                disabled: isDisabled(element),
                isOn: activeBinding(for: element)
            )
        }
    }

    // MARK: - activeElements

    // $activeElements binding — synthesized by @Binding (hand-written accessor removed)

    // MARK: - Init

    // init(elements:selectElement:disableItem:selectedElement:activeElements:)
    init(
        elements: [Element],
        selectElement: @escaping (Element) -> Void,
        disableItem: ((Element) -> Bool)? = nil,
        selectedElement: Binding<Element>,
        activeElements: Binding<[Element]>
    ) {
        self.elements = elements
        self.selectElement = selectElement
        self.disableItem = disableItem
        self._selectedElement = selectedElement
        self._activeElements = activeElements
    }

    // Helper: check if element is selected
    private func isSelected(_ element: Element) -> Bool {
        element == selectedElement
    }

    // Helper: check if element is disabled
    private func isDisabled(_ element: Element) -> Bool {
        disableItem?(element) ?? false
    }

    // Helper: create toggle binding for element
    private func activeBinding(for element: Element) -> Binding<Bool> {
        Binding(
            get: { activeElements.contains(element) },
            set: { newValue in
                if newValue {
                    if !activeElements.contains(element) {
                        activeElements.append(element)
                    }
                } else {
                    activeElements.removeAll { $0 == element }
                }
            }
        )
    }
}