import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation
import SwiftUI
import SwiftData

// MARK: - NotesWidgetView

// Displays selected note with other notes in horizontal stack
// The selected note is edited
//   in place (NoteInlineEditor: native SwiftUI rich-text TextEditor since 2026-10-20; was RichTextKit) on a quinary card with a compact format bar —
//   open-in-window on the left, A (Bigger / Smaller), B, I, U on the right (bold / italic /
//   underline toggles reflect the selection). A narrow column on the right switches between the
//   most recent notes (first letter on a glass circle; selected = accent) and adds a note.
//   Right-click a note in the column to open it in a window or delete it.
struct NotesWidgetView: View {

    // @Query moved out of the computed properties (property wrappers can't be local).
    // DN_CLT_HARNESS: the CLT has no SwiftDataMacros, so the harness uses a plain empty array.
    #if DN_CLT_HARNESS
    private var notes: [Note] { [] }
    #else
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    #endif

    @Environment(\.modelContext) private var modelContext

    @StoredSetting(.notesWidgetSettings) private var settings

    @State private var selectedID: PersistentIdentifier?
    @State private var formatting = NoteTextFormatting()

    /// Notes in the switcher column (most recently edited first).
    private static let columnCount = 4

    private var selectedNote: Note? {
        if let selectedID, let note = notes.first(where: { $0.persistentModelID == selectedID }) { return note }
        return notes.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            editorCard
            switcherColumn
        }
        .nookWidgetFrame()
        .nookWidgetGalleryHook()
    }

    // MARK: Editor

    @ViewBuilder
    private var editorCard: some View {
        VStack(spacing: 0) {
            if let note = selectedNote, note.isCodeMode {
                TextEditor(text: Binding(get: { note.codeText }, set: { note.codeText = $0; note.updatedAt = Date() }))
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .id(note.persistentModelID)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
            } else if let note = selectedNote {
                NoteInlineEditor(
                    attributedString: Binding(
                        get: { note.richText },
                        set: { newValue in
                            note.richText = newValue
                            note.updatedAt = Date()
                        }
                    ),
                    formatting: formatting
                )
                .id(note.persistentModelID)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .onDisappear { try? modelContext.save() }
            } else {
                Button(action: newNote) {
                    Text("Write a note…")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("New Note"))
            }
            formatBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nookCard()
    }

    private var formatBar: some View {
        HStack(spacing: 2) {
            Button {
                if let note = selectedNote {
                    try? modelContext.save()
                    NoteEditorWindows.shared.open(note)
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(selectedNote == nil)
            .help(Text("Open in Window"))
            .accessibilityLabel(Text("Open in Window"))

            Spacer(minLength: 2)

            Menu {
                Button("Bigger") { formatting.stepFontSize(2) }
                Button("Smaller") { formatting.stepFontSize(-2) }
            } label: {
                Text(verbatim: "A")
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22, height: 20)
            .help(Text("Text Size"))
            .accessibilityLabel(Text("Text Size"))

            styleButton(.bold, key: "b", label: Text("Bold")) {
                Text(verbatim: "B").font(.system(size: 12, weight: .bold))
            }
            styleButton(.italic, key: "i", label: Text("Italic")) {
                Text(verbatim: "I").font(.system(size: 12)).italic()
            }
            styleButton(.underline, key: "u", label: Text("Underline")) {
                Text(verbatim: "U").font(.system(size: 12)).underline()
            }
        }
        .disabled(selectedNote == nil)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private func styleButton<L: View>(_ style: NoteTextFormatting.Style, key: KeyEquivalent, label: Text,
                                      @ViewBuilder content: () -> L) -> some View {
        let isOn = formatting.hasStyle(style)
        return Button {
            formatting.toggle(style)
        } label: {
            content()
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary.opacity(isOn ? 1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Switcher column

    private var switcherColumn: some View {
        VStack(spacing: 6) {
            ForEach(Array(notes.prefix(Self.columnCount)), id: \.persistentModelID) { note in
                NoteSwitcherButton(note: note, isSelected: note.persistentModelID == selectedNote?.persistentModelID) {
                    try? modelContext.save()
                    withAnimation(.snappy) { selectedID = note.persistentModelID }
                }
                .contextMenu {
                    Button("Open in Window") { NoteEditorWindows.shared.open(note) }
                    Divider()
                    Button("Delete", role: .destructive) { delete(note) }
                }
            }
            Spacer(minLength: 0)
            NookRoundIconButton(systemImage: "plus", label: Text("New Note"), diameter: 24, action: newNote)
        }
        .frame(width: 24)
        .frame(maxHeight: .infinity)
    }

    private func newNote() {
        let note = Note()
        note.createdAt = Date()
        note.updatedAt = Date()
        modelContext.insert(note)
        try? modelContext.save()
        withAnimation(.snappy) { selectedID = note.persistentModelID }
    }

    private func delete(_ note: Note) {
        if note.persistentModelID == selectedNote?.persistentModelID { selectedID = nil }
        modelContext.delete(note)
        try? modelContext.save()
    }
}

/// One note in the switcher column: the first letter of its title on a glass
///   circle, accent-tinted when selected.
private struct NoteSwitcherButton: View {
    let note: Note
    var isSelected: Bool
    var action: () -> Void

    private var initial: String {
        let title = note.title.trimmingCharacters(in: .whitespaces)
        return title.first.map { String($0).uppercased() } ?? "·"
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: initial)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .nookGlass(in: Circle(), tint: isSelected ? .accentColor : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: note.title.isEmpty ? String(localized: "Untitled Note") : note.title))
        .accessibilityLabel(Text(verbatim: note.title.isEmpty ? String(localized: "Untitled Note") : note.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
