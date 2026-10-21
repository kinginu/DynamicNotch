import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// VStack with Image + Text, font modifier
// nonShockingWhite foregroundColor with opacity 0.4
// foregroundStyle(.nonShockingWhite.opacity(0.4)) on the VStack
struct NoteExpandedMsgView: View {
    var body: some View {
        VStack {
            Image(systemName: "note.text")
                .font(.system(size: 0))

            Text("Expanded note message")
                .opacity(0.6)
        }
        .foregroundStyle(.nonShockingWhite.opacity(0.4))
    }
}