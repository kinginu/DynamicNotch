import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI

// MARK: - NookSettings

struct NookSettings: Preferences, Decodable, Encodable, Equatable, Hashable {

    // MARK: - Stored properties

    var widgets: [NookWidget] = []

    var separatorSpacing: CGFloat = 24 // 2026-10-20 (user decision): default = the maximum of the "Space between widgets" slider (0...24, NookGeneralSettingsTabView)
    var widgetPages: [[NookWidget]]? = nil // F9: page split of `widgets` (nil = one page; optional so older settings decode)

    // MARK: - Computed properties

    // MediaPlayerWidgetView reads `nookSettings.widgetPadding`
    var widgetPadding: Double { Double(separatorSpacing) }

    // Iterates self.widgets, accumulates each widget.prefs.gridSizeType into NookGrid.Point
    // Start with NookGrid.Point.zero, for each widget: result += widget.prefs.gridSizeType
    var widgetsWidth: NookGrid.Point {
        // Start with NookGrid.Point.zero
        var result = NookGrid.Point(value: 0) // Point is a single Double
        for widget in widgets {
            // Get widget.prefs.gridSizeType (existential dispatch)
            let gridSize = widget.prefs.gridSizeType
            // result += gridSize via NookGrid.Point addition operator
            result = NookGrid.Point(value: result.value + Double(gridSize.rawValue)) // no Point + GridSizeType operator
        }
        return result
    }

    // For each widget:
    //   if widget tag == 3 (mirror/separator): compute padding based on ArrayPosition,
    //     result += leftPad + rightPad + (width * 50) + 25.0
    //   else: result += CGFloat(widget.prefs.gridSizeType * 50)
    var widgetsWidthInPoints: CGFloat {
        var result: CGFloat = 0
        let total = widgets.count

        for (index, widget) in widgets.enumerated() {
            // Check widget tag == 3 (mirror/separator case)
            /* tag 3 = mirror widget, which has special width computation */
            if widget == .mirror {
                // Determine padding via ArrayPosition based on (total, index)
                let position = arrayPosition(total: total, i: index)

                // 50 pt per grid cell
                let cellWidth: CGFloat = 50.0 * CGFloat(widgetsWidth.value) // .x → .value

                // Padding based on ArrayPosition:
                //   first:  leftPad=separatorSpacing, rightPad=0
                //   last:   leftPad=0, rightPad=separatorSpacing
                //   middle: leftPad=separatorSpacing, rightPad=separatorSpacing
                //   only:   leftPad=separatorSpacing, rightPad=separatorSpacing
                let leftPad: CGFloat
                let rightPad: CGFloat
                switch position {
                case .first:
                    leftPad = separatorSpacing
                    rightPad = 0
                case .last:
                    leftPad = 0
                    rightPad = separatorSpacing
                case .middle:
                    leftPad = separatorSpacing
                    rightPad = separatorSpacing
                case .only:
                    leftPad = separatorSpacing
                    rightPad = separatorSpacing
                }

                // result += leftPad + rightPad + total + 25.0
                result += leftPad + rightPad + cellWidth + 25.0
            } else {
                // Get widget.prefs.gridSizeType, multiply by 50
                let gridSize = widget.prefs.gridSizeType
                // result += CGFloat(gridSize * 50)
                result += CGFloat(gridSize.rawValue) * 50.0
            }
        }
        return result
    }

    // MARK: - ArrayPosition helper

    /// Determines positional context within the widgets array.
    /// Values: first (leading), last (trailing), middle, only
    private func arrayPosition(total: Int, i: Int) -> ArrayPosition {
        if total == 1 {
            // Only element
            return .only
        } else if i == 0 {
            // First element (total > 1)
            return .first
        } else if i == total - 1 {
            // Last element (total > 1)
            return .last
        } else {
            // Middle element
            return .middle
        }
    }

    private enum ArrayPosition {
        case first
        case last
        case middle
        case only
    }

    // MARK: - Encodable

    // Auto-synthesized Encodable for struct with Codable fields
    // Encodes spacetorSpacing and widgets

    // MARK: - Hashable

    // Auto-synthesized from struct fields

    // MARK: - Equatable (auto-synthesized)

    // MARK: - Default value

    // Default value: empty widgets, zero spacing
    static let defaultProvider: () -> NookSettings = {
        NookSettings(widgets: [], separatorSpacing: 0)
    }

    // MARK: - CodingKeys

}
