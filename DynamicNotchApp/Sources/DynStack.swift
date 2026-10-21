import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

// Stack whose axis is chosen at run time: `isHorizontal` true lays the content out in a VStack,
//   false in an HStack (centred, no spacing).

struct DynStack<Content: View>: View {

    var isHorizontal: Bool

    var content: Content

    var body: some View {
        if isHorizontal {
            VStack(alignment: .center, spacing: 0) {
                content
            }
        } else {
            HStack(alignment: .center, spacing: 0) {
                content
            }
        }
    }
}
