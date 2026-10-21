import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   ScrollView
//     coordinateSpace("scroll")
//     clip(Rectangle())
//     scrollDisabled(true)
//

import SwiftUI

//   A miniature (condensed) preview of a Note, showing either
//   rich text or a code editor depending on isCodeMode.
struct NoteMiniatureView: View {

    // Note reference passed in; the miniature reads its content
    var note: Note              // provides isCodeMode, richText, codeText

    // MARK: - body

    var body: some View {
        // coordinateSpace "scroll", frame flex, clip, scrollDisabled
        ScrollView(.horizontal) {   // scroll axis from layout modifiers
            // _ConditionalContent: branches on isCodeMode
            if note.isCodeMode {                              // from _ConditionalContent
                // a read-only miniature: monospaced text instead of an editor
                Text(verbatim: note.codeText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .padding(8)
                    .frame(
                        minWidth: 0,                          // minWidth: 0
                        idealWidth: nil,
                        maxWidth: .infinity                   // maxWidth: .infinity
                    )                                          // frame modifier
            } else {
                //   foregroundStyle HierarchicalShapeStyle
                // Text displays rich text content or fallback
                Text(AttributedString(note.richText))  // Text needs AttributedString                           // note rich text content
                    .fixedSize()
                    .padding()
                    .foregroundStyle(.secondary)              // HierarchicalShapeStyle → .secondary
            }
        }
        .coordinateSpace(name: "scroll")                      // literal "scroll"

        // .frame maps these constraints
        .frame(
            minWidth: 0,                                      // minWidth: 0
            idealWidth: 1,                                    // idealWidth: 1
            maxWidth: .infinity                               // maxWidth: .infinity
        )

        //   Internal type maps to SwiftUI's .clipped() or .clipShape(Rectangle())
        .clipped(antialiased: true)                            // clip → clipped

        .scrollDisabled(true)                                 // scrollDisabled(true)
    }
}