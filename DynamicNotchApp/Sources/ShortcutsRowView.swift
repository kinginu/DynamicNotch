import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

/// Horizontal row of shortcut views.
///
///   1. HStack with ForEach over enumerated shortcuts strings
///   2. Each item: ShortcutView with .padding(EdgeInsets) and .frame
///   3. Uses _VariadicViewO4Tree with HStackLayout
///   4. .flexFrame with .leading alignment, all dimensions nil except maxHeight .infinity
struct ShortcutsRowView: View {
    // Array of shortcut identifier strings
    var shortcuts: [String] = []

    // HStackLayout wrapping ForEach over enumerated strings
    // Each item: ShortcutView with padding(EdgeInsets) and frame
    // .flexFrame(minWidth: nil, idealWidth: nil, maxWidth: nil,
    //                         minHeight: nil, idealHeight: nil, maxHeight: .infinity,
    //                         alignment: .leading)
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // ForEach over enumerated shortcuts strings
            ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                ShortcutView(shortcutIdentifier: shortcut)
                    // .padding(EdgeInsets) applied to each item
                    .padding(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    // .frame(width:height:alignment:) modifier
                    .frame(height: 32)
            }
        }
        // .flexFrame with .leading alignment
        // All dimensions nil except maxHeight = .infinity
        .frame(
            minWidth: nil,
            idealWidth: nil,
            maxWidth: nil,
            minHeight: nil,
            idealHeight: nil,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

}