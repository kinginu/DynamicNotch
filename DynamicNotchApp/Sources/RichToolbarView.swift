import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct RichToolbarView: View {
    // @ObservedObject for RichTextKit context access
    // RichTextKit dropped → NoteTextFormatting (NoteRichEditor.swift)
    var richTextContext: NoteTextFormatting

    // @State<Bool> for hover-tracking (toggled by hoverRegion closure)
    @State private var isHovering: Bool = false

    // When non-zero, buttons use 15.0×17.0; when zero, 13.0×15.0.
    private var isCompact: Bool { false }

    // HStack(alignment: .center) wrapping 4 RichToolbarButtonView in TupleView
    // Button width/height: compact → 13.0×15.0, normal → 15.0×17.0
    // .compositingGroup()
    // hoverRegion modifier with closure that sets isHovering @State<Bool>
    var body: some View {
        // Button size selection: if compact → 13.0×15.0, else → 15.0×17.0
        let buttonWidth:  CGFloat = isCompact ? 13.0 : 15.0
        let buttonHeight: CGFloat = isCompact ? 15.0 : 17.0

        // HStack(alignment: .center, spacing: default) with TupleView of 4 buttons
        HStack(alignment: .center) {
            // 4 RichToolbarButtonView instances in TupleView
            RichToolbarButtonView(systemName: "bold", richTextContext: richTextContext)  // args
                .frame(width: buttonWidth, height: buttonHeight)
            RichToolbarButtonView(systemName: "italic", richTextContext: richTextContext)  // args
                .frame(width: buttonWidth, height: buttonHeight)
            RichToolbarButtonView(systemName: "underline", richTextContext: richTextContext)  // args
                .frame(width: buttonWidth, height: buttonHeight)
            RichToolbarButtonView(systemName: "strikethrough", richTextContext: richTextContext)  // args
                .frame(width: buttonWidth, height: buttonHeight)
        }
        .padding(3.0)
        // compositingGroup() modifier
        .compositingGroup()
        // hoverRegion modifier: closure toggles isHovering @State<Bool>
        .onHover { hovering in
            // isHovering @State<Bool> setter from closure __d_...cfU0_.c
            isHovering = hovering
        }
    }

}