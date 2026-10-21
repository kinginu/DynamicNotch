import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// One bullet row of the changelog.
struct ChangelogItem: View {
    var text: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("-").foregroundStyle(.secondary)
            Text(text)
        }
    }
}
