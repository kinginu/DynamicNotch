import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Multi-select picker with element selection and active element tracking
// made generic over the preview/settings views supplied by the call sites
//   (WidgetsSettingsTabView, LiveActivitiesCustomizeSettingsTabView); selection is local state.
struct MultipleSettingsPicker<Element: Hashable, Preview: View, SettingsContent: View>: View {

    // Available elements for selection
    private let elements: [Element]

    // Selected element (defaults to the first element)
    @State private var selection: Element?

    // Active elements binding
    @Binding private var activeElements: [Element]

    // Optional item disabler
    private let disableItem: ((Element) -> Bool)?

    private let preview: (Element) -> Preview
    private let settings: (Element) -> SettingsContent

    // MARK: - Body

    // Delegates to ElementsListView for rendering
    var body: some View {
        if let current = selection ?? elements.first {
            HStack(alignment: .top, spacing: 0) {
                ElementsListView(
                    elements: elements,
                    selectElement: selectElement,
                    disableItem: disableItem,
                    selectedElement: Binding(get: { current }, set: { selection = $0 }),
                    activeElements: $activeElements
                )
                .frame(width: 200)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    preview(current)
                    settings(current)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            NoOptionsSettingsView()
        }
    }

    // MARK: - selectElement

    // selectElement(_:)
    // Handles element selection
    func selectElement(_ element: Element) {
        selection = element
    }

    // MARK: - Init

    init(
        elements: [Element],
        activeElements: Binding<[Element]>,
        disableItem: ((Element) -> Bool)? = nil,
        @ViewBuilder preview: @escaping (Element) -> Preview,
        @ViewBuilder settings: @escaping (Element) -> SettingsContent
    ) {
        self.elements = elements
        self._activeElements = activeElements
        self.disableItem = disableItem
        self.preview = preview
        self.settings = settings
    }
}
