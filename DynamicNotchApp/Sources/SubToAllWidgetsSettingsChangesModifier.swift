import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Combine
import SwiftUI

// ViewModifier that subscribes to widget settings changes
//   and updates all widgets when settings are modified externally.
//   Acts as a bridge between settings persistence and widget views.
struct SubToAllWidgetsSettingsChangesModifier: ViewModifier {

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UserDefaults.didChangeNotification
                )
                .debounce(for: .seconds(0.1), scheduler: DispatchQueue.main)
            ) { _ in
                // Widget settings changed; views will re-render
                //   via @Environment / @State bindings automatically
            }
    }
}
