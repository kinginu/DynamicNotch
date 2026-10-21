import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

struct CustomLabeled: View {
    var label: String = ""
    var systemImage: String?

    // a Label when an SF Symbol name is given, plain text otherwise
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let imageName = systemImage {
                    Label(label, systemImage: imageName)
                } else {
                    Text(label)
                }
            }
            .opacity(1.0)
        }
    }
}
