import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   Button(action: closure → toggles richTextKit context style)
//   → .help(systemName)
//   → .buttonStyle(ToolbarButtonStyle())
//   → HoverRegionModifier
//
// Properties:
//   @ObservedObject<RichTextContext> richTextContext
//   @State<Bool> checked
//

import SwiftUI

//   A toolbar button that toggles a rich text style (bold/italic/underline/etc.)
//   identified by its systemName, with hover interaction for the toolbar.
struct RichToolbarButtonView: View {

    // Used by .help() modifier
    // Read by onTapGesture for rich text style toggling
    let systemName: String

    //   Captures richTextKit context state for toggling text styles
    // RichTextKit dropped → NoteTextFormatting (NoteRichEditor.swift)
    var richTextContext: NoteTextFormatting

    // reflects the style at the selection instead of a local toggle
    private var checked: Bool { Self.style(for: systemName).map(richTextContext.hasStyle) ?? false }

    // MARK: - body

    var body: some View {
        //   allocated Image(systemName:) from self.systemName string property
        Button(action: {                                           // Button action
            // Toggles richTextKit context style based on systemName
            // The specific style toggling depends on systemName value
            // toggleStyle takes a RichTextStyle; map the SF Symbol name to it
            if let style = Self.style(for: systemName) {
                richTextContext.toggle(style)                      // style toggling
            }
        }) {
            //   Creates Image(systemName:) from self.systemName
            Image(systemName: systemName)
                .foregroundColor(                                   // tint from checked state
                    checked ? .accentColor : .secondary             // visual feedback
                )
        }
        .help(systemName)                                          // systemName as help text

        .buttonStyle(ToolbarButtonStyle())                         // ToolbarButtonStyle

        //   Used for toolbar hover interaction tracking
        .onHover { hovering in                                     // HoverRegionModifier
            // Hover state tracking for toolbar
        }
    }

    // SF Symbol name → formatting style
    static func style(for systemName: String) -> NoteTextFormatting.Style? {
        switch systemName {
        case "bold": return .bold
        case "italic": return .italic
        case "underline": return .underline
        case "strikethrough": return .strikethrough
        default: return nil
        }
    }
}
