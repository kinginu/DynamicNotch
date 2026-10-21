import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Lists the Nook widgets in order and lets the
// user move them (NookSettings.widgets).
struct ReorderWidgetsView: View {
    @StoredSetting(.nookSettings) private var nookSettings

    var body: some View {
        List {
            ForEach(nookSettings.widgets) { widget in
                Label(widget.name, systemImage: widget.icon)
            }
            .onMove { from, to in
                nookSettings.widgets.move(fromOffsets: from, toOffset: to)
            }
        }
        .frame(minHeight: 120)
    }
}
