// Shared Nook widget helpers: stored-setting keys for the Quick Apps / Shortcuts widget contents,
// the Settings ▸ Nook navigation state, the small capsule / icon button styles used inside
// widgets, and the note editor window opened from the Notes widget.
import AppKit
import Observation
import SwiftData
import SwiftUI
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "notes")

// MARK: - Stored-setting keys

extension StoredKeys {
    /// Quick Apps widget: application bundle paths, in display order.
    static let quickAppsPaths = Key<[String]>(SettingKey.quickAppsPaths, default: [])
    /// Shortcuts widget: names of the Shortcuts (Shortcuts.app) shown in the widget, in order.
    static let shortcutsWidgetSelection = Key<[String]>(SettingKey.shortcutsWidgetSelection, default: [])
}

// MARK: - Settings navigation

/// Which tab of Settings ▸ Nook is shown, and which widget is selected in the Widgets tab.
/// Lets the notch ("Open Settings" buttons) and DebugHooks jump to a specific place.
@MainActor
@Observable
final class NookSettingsNavigation {
    static let shared = NookSettingsNavigation()

    enum Tab: String, Hashable, CaseIterable {
        case general, widgets, dropArea
    }

    var tab: Tab = .general
    var widget: NookWidget? = nil

    /// Opens Settings ▸ Nook ▸ Widgets with `widget` selected.
    static func showWidgetSettings(_ widget: NookWidget? = nil) {
        shared.tab = .widgets
        if let widget { shared.widget = widget }
        WindowsManager.shared.showSettings(pane: AppSettings.PaneIdentifier("nook"))
    }
}

// MARK: - Shared widget styling

/// Small capsule button used inside widgets (dark notch background).
struct NookCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(Color.white.opacity(0.9))
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.25 : (prominent ? 0.2 : 0.12)))
            )
            .contentShape(Capsule())
    }
}

/// Icon-only round button used inside widgets.
struct NookIconButtonStyle: ButtonStyle {
    var size: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.5, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(Color.white.opacity(0.85))
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0.12)))
            .contentShape(Circle())
    }
}

// MARK: - Note editor window

/// Note editor windows opened from the Notes widget (one window per note; reopening a note brings
/// its window to the front).
@MainActor
final class NoteEditorWindows {
    static let shared = NoteEditorWindows()

    // The willClose observer token is kept with its window and removed when the window closes.
    private struct Entry {
        let window: NSWindow
        let note: Note
        let closeObserver: NSObjectProtocol
    }
    private var windows: [PersistentIdentifier: Entry] = [:]
    private var saveObserver: NSObjectProtocol?

    private init() {
        // A note deleted elsewhere (Notes widget ▸ Delete) must not stay open: the editor would then
        // read/write an invalidated SwiftData model, which traps. Close the editor of any note that
        // a save reports as deleted. (App-lifetime singleton: the observer is never removed.)
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil,
                                                              queue: .main) { [weak self] note in
            let deleted = (note.userInfo?[ModelContext.NotificationKey.deletedIdentifiers.rawValue]
                as? [PersistentIdentifier]) ?? []
            MainActor.assumeIsolated { self?.closeDeleted(Set(deleted)) }
        }
    }

    func open(_ note: Note) {
        let id = note.persistentModelID
        if let existing = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = note.title.isEmpty ? String(localized: "Untitled Note") : note.title
        window.contentView = NSHostingView(rootView: NoteEditorWindowContent(note: note).nookModelContainer())
        window.center()
        window.level = .floating
        let token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                do {
                    try NookModelContainer.shared?.mainContext.save()
                } catch {
                    logger.error("note not saved on window close: \(String(describing: error), privacy: .public)")
                }
                self?.forget(id)
            }
        }
        windows[id] = Entry(window: window, note: note, closeObserver: token)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the editor window of `id`, if open (e.g. right before the note is deleted).
    func close(_ id: PersistentIdentifier) {
        guard let entry = windows[id] else { return }
        // detach the editor from the model first so nothing touches it while the window goes away
        entry.window.contentView = nil
        entry.window.close() // → willClose → forget(id)
        forget(id)
    }

    private func forget(_ id: PersistentIdentifier) {
        guard let entry = windows.removeValue(forKey: id) else { return }
        NotificationCenter.default.removeObserver(entry.closeObserver)
    }

    private func closeDeleted(_ deletedIDs: Set<PersistentIdentifier>) {
        for (id, entry) in windows where deletedIDs.contains(id) || entry.note.isDeleted || entry.note.modelContext == nil {
            close(id)
        }
    }
}

/// Note editor window content (2026-10-20: native rich text). Rich notes use NativeRichTextEditor
/// (SwiftUI `TextEditor` on AttributedString, NoteRichEditor.swift) with a B / I / U / S and text
/// size bar (⌘B / ⌘I / ⌘U, ⌘+ / ⌘-); code notes use the monospaced NoteCodeEditor. Formatting is
/// kept (the previous plain-text editor flattened it on the first edit).
private struct NoteEditorWindowContent: View {
    let note: Note
    @State private var formatting = NoteTextFormatting()

    var body: some View {
        VStack(spacing: 0) {
            if note.isCodeMode {
                NoteCodeEditor(note: note, fontSize: 13)
            } else {
                formatBar
                Divider()
                NativeRichTextEditor(
                    attributedString: Binding(
                        get: { note.richText },
                        set: { newValue in
                            // never touch a note that was deleted while the editor was open
                            guard !note.isDeleted, note.modelContext != nil else { return }
                            note.richText = newValue
                            note.updatedAt = Date()
                            NSApp.keyWindow?.title = note.title.isEmpty ? String(localized: "Untitled Note") : note.title
                        }
                    ),
                    formatting: formatting,
                    baseFont: .systemFont(ofSize: 14)
                )
                .padding(12)
            }
        }
        .frame(minWidth: 320, minHeight: 240)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var formatBar: some View {
        HStack(spacing: 4) {
            styleButton(.bold, symbol: "bold", key: "b", label: Text("Bold"))
            styleButton(.italic, symbol: "italic", key: "i", label: Text("Italic"))
            styleButton(.underline, symbol: "underline", key: "u", label: Text("Underline"))
            styleButton(.strikethrough, symbol: "strikethrough", key: "x", modifiers: [.command, .shift],
                        label: Text("Strikethrough"))
            Divider().frame(height: 16)
            Button { formatting.stepFontSize(-2) } label: { Image(systemName: "textformat.size.smaller") }
                .keyboardShortcut("-", modifiers: .command)
                .help(Text("Smaller"))
                .accessibilityLabel(Text("Smaller"))
            Button { formatting.stepFontSize(2) } label: { Image(systemName: "textformat.size.larger") }
                .keyboardShortcut("+", modifiers: .command)
                .help(Text("Bigger"))
                .accessibilityLabel(Text("Bigger"))
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func styleButton(_ style: NoteTextFormatting.Style, symbol: String, key: KeyEquivalent,
                             modifiers: EventModifiers = .command, label: Text) -> some View {
        let isOn = formatting.hasStyle(style)
        return Button { formatting.toggle(style) } label: {
            Image(systemName: symbol)
                .frame(width: 22, height: 20)
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary.opacity(isOn ? 1 : 0)))
                .contentShape(Rectangle())
        }
        .keyboardShortcut(key, modifiers: modifiers)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
