import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   @State _maximumLabelWidth
//
//
//   GeometryReader<VStack<TupleView<
//

import SwiftUI

//   Settings tab for configuring indicator pipeline visible sections.
struct PipelinesSettingsTabView: View {

    //   Used by Settings.Container to coordinate label widths
    @State private var maximumLabelWidth: CGFloat = 0          // from @State symbol

    // MARK: - body

    var body: some View {

        // native settings window: grouped Form instead of sindresorhus/Settings'
        //   Settings.Container(contentWidth: 520.0) / Settings.Section
        Form {

            // First section: brightness indicator group
            Section {
                //   GeometryReader<VStack<
                //     )
                //   >>
                GeometryReader { proxy in                     // GeometryReader
                    VStack(alignment: .leading) {
                        BrightnessIndicatorValueView(
                            brightness: 0.5,                // default value
                            glowThreshold: 0.8               // real init is (brightness:glowThreshold:)
                        )
                        .frame(width: proxy.size.width)

                        //   may be BrightnessIndicatorCometView or similar
                        BrightnessIndicatorCometView()       // nearest match in codebase
                            .frame(width: proxy.size.width)
                    }
                }
            }
            // (Inherited from Container's layout)

            // Additional sections for other pipelines
            Section {
                VolumeIndicatorValueView()                    // companion section
            }
        }
        .formStyle(.grouped)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading                             // topLeading alignment
        )
    }
}

// MARK: - VolumeIndicatorValueView (placeholder module)
// Referenced by PipelinesSettingsTabView container; defined elsewhere