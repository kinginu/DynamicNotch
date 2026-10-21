import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Main note editing/display view with rich text editing support
struct NoteView: View {

    // The note being edited
    @State var note: Note

    // Whether in code editing mode
    @State private var isCodeMode: Bool = false

    // MARK: - Body

    // Card-like note view with rich text editor and mode toggling
    var body: some View {
        VStack(spacing: 0) {
            // Header bar with mode toggle
            HStack {
                Image(systemName: note.icon)
                    .foregroundStyle(.secondary)

                Text(note.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    isCodeMode.toggle()
                } label: {
                    Image(systemName: isCodeMode ? "text.alignleft" : "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Editor area
            if isCodeMode {
                ScrollView {
                    TextEditor(text: $note.codeText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                }
            } else {
                ScrollView {
                    Text(AttributedString(note.richText))  // Text needs AttributedString
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .modifier(ShapeModifier())
    }
}

// MARK: - NoteView.ShapeModifier

extension NoteView {
    struct ShapeModifier: ViewModifier {

        // MARK: - cardBackground

        // cardBackground() -> some View
        // Glass-morphic card background with rounded corners and shadow
        func cardBackground() -> some View {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }

        // MARK: - Body

        // body(content:) -> some View
        // Wraps content with card background
        func body(content: Content) -> some View {
            content
                .padding(12)
                .background(cardBackground())
                .padding(4)
        }
    }
}

// Note text binding extension — removed: `codeText` is now a stored @Model property (Note.swift)
