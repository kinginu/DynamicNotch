// Code-mode note editor.
//
// A plain monospaced NSTextView without syntax highlighting, bound to `note.codeText`, with a
//   vertical edge fade (top 20 / bottom 48, ease-in-out) drawn with an eased SwiftUI `Gradient`
//   (EasedGradient below).
import AppKit
import SwiftUI
import SwiftData

struct NoteCodeEditor: View {
    var note: Note
    var fontSize: CGFloat = 12

    init(note: Note, fontSize: CGFloat = 12) {
        self.note = note
        self.fontSize = fontSize
    }

    var body: some View {
        MonospacedTextView(
            text: Binding(
                get: { note.codeText },
                set: { newValue in
                    // never touch a note deleted while the editor was open
                    guard !note.isDeleted, newValue != note.codeText else { return }
                    note.codeText = newValue
                    note.updatedAt = Date()
                }
            ),
            fontSize: fontSize,
            inset: CGSize(width: 8, height: 12)
        )
        .mask {
            VStack(spacing: 0) {
                LinearGradient(gradient: EasedGradient.gradient(from: .clear, to: .black), startPoint: .top, endPoint: .bottom)
                    .frame(height: 12)
                Rectangle()
                LinearGradient(gradient: EasedGradient.gradient(from: .black, to: .clear), startPoint: .top, endPoint: .bottom)
                    .frame(height: 20)
            }
        }
        .id(note.persistentModelID)
    }
}

// MARK: - Eased gradient (SmoothGradient replacement)

/// A two-colour gradient with extra stops placed along a `UnitCurve`, which avoids the visible
/// banding / hard edge of a linear two-stop gradient — what SmoothGradient's SmoothLinearGradient
/// provided.
enum EasedGradient {
    static func gradient(from start: Color, to end: Color, curve: UnitCurve = .easeInOut, steps: Int = 16) -> Gradient {
        let count = max(steps, 2)
        let stops = (0...count).map { index -> Gradient.Stop in
            let location = Double(index) / Double(count)
            return Gradient.Stop(color: start.mix(with: end, by: curve.value(at: location)), location: location)
        }
        return Gradient(stops: stops)
    }
}

// MARK: - Monospaced NSTextView

/// Plain-text, monospaced `NSTextView` in a scroll view: no rich text, no smart quotes / dashes /
/// replacements / spelling, undo enabled, transparent background, follows the colour scheme.
struct MonospacedTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 12
    var inset: CGSize = CGSize(width: 8, height: 8)

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MonospacedTextView
        init(_ parent: MonospacedTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = inset
        textView.string = text
        textView.setAccessibilityLabel(String(localized: "Note"))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            let length = (text as NSString).length
            textView.selectedRanges = selection.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
            }
        }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != font { textView.font = font }
        let name: NSAppearance.Name = context.environment.colorScheme == .dark ? .darkAqua : .aqua
        if scrollView.appearance?.name != name { scrollView.appearance = NSAppearance(named: name) }
    }
}
