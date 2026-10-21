// Notes rich-text editing on the native macOS 26 SwiftUI `TextEditor(text: Binding<AttributedString>)`.
//
// This file holds the whole editing stack:
//   - NoteTextFormatting — the format-bar ↔ editor channel (replaces RichTextContext): B / I / U /
//     S toggles, Bigger / Smaller, and the styles at the current selection for button highlights.
//   - NoteRichText — NSAttributedString (the SwiftData storage type, RTF through
//     NSAttributedStringTransformer; unchanged) ↔ SwiftUI AttributedString conversion.
//   - NativeRichTextEditor — TextEditor + AttributedTextSelection bound to an NSAttributedString.
//   - NoteRichEditor (expanded note) and NoteInlineEditor (Nook Notes widget).
//
// Conversion keeps font (family / size / bold / italic), non-neutral text colour, underline,
// strikethrough and links. Paragraph styles (alignment, lists, tabs) of notes written by the
// earlier RichTextKit-based editor are not represented in SwiftUI's rich-text model and are dropped
// the first time such a note is edited (opening it does not rewrite it). Neutral (grey / black /
// white) colours are dropped on import so text follows the light / dark appearance (the old editor
// used `usesAdaptiveColorMappingForDarkAppearance` for the same reason).
// Storage is unchanged RTF, so (as with RichTextKit) the system font is read back from RTF as
// Helvetica Neue after a save / relaunch; the editor does not reload on such font-only changes.
import AppKit
import SwiftUI
import Observation
import SwiftData

// MARK: - Formatting channel

/// Shared between a format bar and the editor it drives. Buttons call `toggle(_:)` /
/// `stepFontSize(_:)`; the editor applies the queued commands to its selection and publishes the
/// styles found at the selection (`hasStyle(_:)`).
@Observable
final class NoteTextFormatting {
    enum Style: Hashable, CaseIterable {
        case bold, italic, underline, strikethrough
    }

    enum Command: Equatable {
        case toggle(Style)
        case stepFontSize(CGFloat)
    }

    private(set) var activeStyles: Set<Style> = []
    /// Bumped for every queued command; editors observe it with `onChange`.
    private(set) var commandSerial: Int = 0
    @ObservationIgnored private var pending: [Command] = []

    init() {}

    func hasStyle(_ style: Style) -> Bool { activeStyles.contains(style) }
    func toggle(_ style: Style) { perform(.toggle(style)) }
    func stepFontSize(_ points: CGFloat) { perform(.stepFontSize(points)) }

    func perform(_ command: Command) {
        pending.append(command)
        commandSerial &+= 1
    }

    func takePending() -> [Command] {
        defer { pending.removeAll() }
        return pending
    }

    func setActiveStyles(_ styles: Set<Style>) {
        if styles != activeStyles { activeStyles = styles }
    }
}

// MARK: - NSAttributedString ↔ AttributedString

enum NoteRichText {
    typealias FontKey = AttributeScopes.SwiftUIAttributes.FontAttribute
    typealias ColorKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
    typealias UnderlineKey = AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
    typealias StrikeKey = AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute
    typealias LinkKey = AttributeScopes.FoundationAttributes.LinkAttribute

    /// Storage → editor. AppKit attributes become their SwiftUI counterparts.
    static func attributedString(from ns: NSAttributedString) -> AttributedString {
        var out = AttributedString(ns.string)
        let full = NSRange(location: 0, length: ns.length)
        ns.enumerateAttributes(in: full) { attrs, nsRange, _ in
            guard let range = Range(nsRange, in: out) else { return }
            var container = AttributeContainer()
            if let font = attrs[.font] as? NSFont {
                container[FontKey.self] = Font(font as CTFont)
            }
            if let color = attrs[.foregroundColor] as? NSColor, !isNeutral(color) {
                container[ColorKey.self] = Color(nsColor: color)
            }
            if let raw = (attrs[.underlineStyle] as? NSNumber)?.intValue, raw != 0 {
                container[UnderlineKey.self] = Text.LineStyle(nsUnderlineStyle: NSUnderlineStyle(rawValue: raw)) ?? .single
            }
            if let raw = (attrs[.strikethroughStyle] as? NSNumber)?.intValue, raw != 0 {
                container[StrikeKey.self] = Text.LineStyle(nsUnderlineStyle: NSUnderlineStyle(rawValue: raw)) ?? .single
            }
            if let url = attrs[.link] as? URL {
                container[LinkKey.self] = url
            } else if let string = attrs[.link] as? String, let url = URL(string: string) {
                container[LinkKey.self] = url
            }
            out[range].mergeAttributes(container)
        }
        return out
    }

    /// Editor → storage. Runs without a font get `baseFont` (what the editor shows for them).
    static func nsAttributedString(from text: AttributedString, baseFont: NSFont,
                                   context: Font.Context) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs {
            var attrs: [NSAttributedString.Key: Any] = [.font: nsFont(run[FontKey.self], base: baseFont, context: context)]
            if let color = run[ColorKey.self] { attrs[.foregroundColor] = NSColor(color) }
            if let style = run[UnderlineKey.self] { attrs[.underlineStyle] = NSUnderlineStyle(style).rawValue }
            if let style = run[StrikeKey.self] { attrs[.strikethroughStyle] = NSUnderlineStyle(style).rawValue }
            if let url = run[LinkKey.self] { attrs[.link] = url }
            result.append(NSAttributedString(string: String(text[run.range].characters), attributes: attrs))
        }
        return result
    }

    static func nsFont(_ font: Font?, base: NSFont, context: Font.Context) -> NSFont {
        guard let font else { return base }
        return font.resolve(in: context).ctFont as NSFont
    }

    /// Greys, black and white: the "default" text colours that should follow the appearance.
    static func isNeutral(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return true }
        return rgb.saturationComponent < 0.08 || rgb.brightnessComponent < 0.08
    }

    /// Styles present at the selection (the typing attributes for an insertion point).
    static func styles(of container: AttributeContainer, baseFont: NSFont,
                       context: Font.Context) -> Set<NoteTextFormatting.Style> {
        var styles: Set<NoteTextFormatting.Style> = []
        let traits = NSFontManager.shared.traits(of: nsFont(container[FontKey.self], base: baseFont, context: context))
        if traits.contains(.boldFontMask) { styles.insert(.bold) }
        if traits.contains(.italicFontMask) { styles.insert(.italic) }
        if container[UnderlineKey.self] != nil { styles.insert(.underline) }
        if container[StrikeKey.self] != nil { styles.insert(.strikethrough) }
        return styles
    }
}

// MARK: - Native editor

/// SwiftUI rich-text `TextEditor` bound to a note's `NSAttributedString`. Writes back only when the
/// user changes the text (loading a note never rewrites it).
struct NativeRichTextEditor: View {
    @Binding var attributedString: NSAttributedString
    var formatting: NoteTextFormatting
    var baseFont: NSFont = .systemFont(ofSize: 13)

    @Environment(\.fontResolutionContext) private var fontContext

    @State private var text = AttributedString()
    @State private var selection = AttributedTextSelection()
    /// The text as last loaded from / written to the binding (to tell user edits from reloads).
    @State private var syncedText = AttributedString()
    @State private var syncedSource: NSAttributedString?

    private static let fontManager = NSFontManager.shared

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .font(Font(baseFont as CTFont))
            .scrollContentBackground(.hidden)
            .onAppear {
                _ = formatting.takePending()   // drop commands queued while no rich editor was shown
                load(attributedString)
            }
            .onChange(of: attributedString) { _, newValue in
                // Reload only for a different text (another editor of the same note, a deleted /
                // switched note). A save re-materializes the RTF-transformed attribute as a new
                // object with re-resolved fonts; reloading on that would reset the caret mid-typing.
                if newValue.string != syncedSource?.string { load(newValue) }
            }
            .onChange(of: text) { _, newValue in
                guard newValue != syncedText else { return }
                let ns = NoteRichText.nsAttributedString(from: newValue, baseFont: baseFont, context: fontContext)
                syncedText = newValue
                syncedSource = ns
                attributedString = ns
                publishStyles()
            }
            .onChange(of: selection) { _, _ in publishStyles() }
            .onChange(of: formatting.commandSerial) { _, _ in applyPending() }
    }

    private func load(_ ns: NSAttributedString) {
        let converted = NoteRichText.attributedString(from: ns)
        syncedSource = ns
        syncedText = converted
        if converted != text {
            text = converted
            selection = AttributedTextSelection()
        }
        publishStyles()
    }

    /// Attribute containers under the selection: each run of a range selection, or the typing
    /// attributes of an insertion point.
    private func selectedContainers() -> [AttributeContainer] {
        switch selection.indices(in: text) {
        case .insertionPoint:
            return [selection.typingAttributes(in: text)]
        case .ranges(let ranges):
            let containers = ranges.ranges.flatMap { range in text[range].runs.map(\.attributes) }
            return containers.isEmpty ? [selection.typingAttributes(in: text)] : containers
        }
    }

    /// A style is active when every selected run has it (TextEdit's rule).
    private func activeStyles() -> Set<NoteTextFormatting.Style> {
        let sets = selectedContainers().map { NoteRichText.styles(of: $0, baseFont: baseFont, context: fontContext) }
        guard var result = sets.first else { return [] }
        for set in sets.dropFirst() { result.formIntersection(set) }
        return result
    }

    private func publishStyles() {
        formatting.setActiveStyles(activeStyles())
    }

    private func applyPending() {
        let commands = formatting.takePending()
        guard !commands.isEmpty else { return }
        for command in commands {
            let active = activeStyles()
            let change: (inout AttributeContainer) -> Void = { container in
                apply(command, active: active, to: &container)
            }
            if case .ranges(let ranges) = selection.indices(in: text) {
                // Range selection: restyle run by run so each keeps its own font / attributes
                // (`transformAttributes(in:)` hands the body one container for the whole selection).
                // Work in character offsets (attribute edits re-split runs, invalidating indices) and
                // restore the selection afterwards (`transform(updating:)` lost it here).
                var string = text
                let chars = string.characters
                func offset(_ index: AttributedString.Index) -> Int { chars.distance(from: chars.startIndex, to: index) }
                let selected = ranges.ranges.map { (offset($0.lowerBound), offset($0.upperBound)) }
                let spans = ranges.ranges.flatMap { range in
                    string[range].runs.map { (offset($0.range.lowerBound), offset($0.range.upperBound), $0.attributes) }
                }
                for (lower, upper, attributes) in spans {
                    var container = attributes
                    change(&container)
                    let start = string.characters.index(string.startIndex, offsetBy: lower)
                    let end = string.characters.index(string.startIndex, offsetBy: upper)
                    string[start..<end].setAttributes(container)
                }
                text = string
                let restored = selected.map { lower, upper in
                    string.characters.index(string.startIndex, offsetBy: lower)..<string.characters.index(string.startIndex, offsetBy: upper)
                }
                selection = AttributedTextSelection(ranges: RangeSet(restored))
            } else {
                text.transformAttributes(in: &selection, body: change)
            }
        }
        publishStyles()
    }

    private func apply(_ command: NoteTextFormatting.Command, active: Set<NoteTextFormatting.Style>,
                       to container: inout AttributeContainer) {
        let current = NoteRichText.nsFont(container[NoteRichText.FontKey.self], base: baseFont, context: fontContext)
        switch command {
        case .toggle(.bold):
            let font = active.contains(.bold)
                ? Self.fontManager.convert(current, toNotHaveTrait: .boldFontMask)
                : Self.fontManager.convert(current, toHaveTrait: .boldFontMask)
            container[NoteRichText.FontKey.self] = Font(font as CTFont)
        case .toggle(.italic):
            let font = active.contains(.italic)
                ? Self.fontManager.convert(current, toNotHaveTrait: .italicFontMask)
                : Self.fontManager.convert(current, toHaveTrait: .italicFontMask)
            container[NoteRichText.FontKey.self] = Font(font as CTFont)
        case .toggle(.underline):
            container[NoteRichText.UnderlineKey.self] = active.contains(.underline) ? nil : .single
        case .toggle(.strikethrough):
            container[NoteRichText.StrikeKey.self] = active.contains(.strikethrough) ? nil : .single
        case .stepFontSize(let points):
            let size = min(max(current.pointSize + points, 8), 72)
            container[NoteRichText.FontKey.self] = Font(Self.fontManager.convert(current, toSize: size) as CTFont)
        }
    }
}

// MARK: - Expanded note editor

struct NoteRichEditor: View {
    private var note: Note

    @Environment(\.expandedNoteManager) private var expandedNoteManager
    @State private var fallbackFormatting = NoteTextFormatting()

    init(note: Note) {
        self.note = note
    }

    var body: some View {
        // binds the editor to note.richText (RTF-transformed SwiftData attribute)
        NativeRichTextEditor(
            attributedString: Binding(
                get: { note.richText },
                set: { note.richText = $0; note.updatedAt = Date() }
            ),
            formatting: expandedNoteManager?.richTextContext ?? fallbackFormatting,
            baseFont: .systemFont(ofSize: 14)
        )
        .padding(12)
        .id(note.persistentModelID)
    }
}

// MARK: - Inline editor (Nook Notes widget)

/// Inline rich-text editor for the Nook Notes widget (widget restyle 2026-10-20):
///   13 pt system font for text without a font, colours follow the notch's (dark) colour scheme,
///   and `formatting` drives B / I / U and Bigger / Smaller from the widget's format bar.
struct NoteInlineEditor: View {
    @Binding var attributedString: NSAttributedString
    var formatting: NoteTextFormatting

    var body: some View {
        NativeRichTextEditor(attributedString: $attributedString, formatting: formatting,
                             baseFont: .systemFont(ofSize: 13))
            .textEditorStyle(.plain)
            .accessibilityLabel(Text("Note"))
    }
}
