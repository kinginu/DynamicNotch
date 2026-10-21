// Calculator widget (2026-10-20). One text field that evaluates as you type
// (CalculatorEngine: arithmetic, %, powers, functions, units, currencies, bases, time zones).
//
// Layout (250 pt × 202 pt, NookWidgetChrome style): header (title + Clear), the field, the result
// line (click copies it; errors show inline in its place), then the last 10 results (click copies
// a result; context menu reuses the expression or removes it). Return adds the current result to
// the history; Esc clears the field; ⌘K focuses the field.
//
// Focus: with "Focus the field when the Nook opens" (default on) the notch window becomes key and
// the field takes the keyboard when the Nook opens. The app that was in front is remembered and
// re-activated when the Nook closes or when the pointer leaves the widget with an empty field —
// an empty, focused field would otherwise keep the notch open (NotchHover keeps the notch open
// while text is being edited, which is what keeps it open while typing).
import SwiftUI
import AppKit

struct CalculatorWidgetView: View {
    @StoredSetting(.calculatorWidgetSettings) private var settings
    @State private var rates = CalculatorRatesStore.shared
    @State private var history = CalculatorHistoryStore.shared
    @State private var input = ""
    @State private var copiedID: String?
    @State private var window: NSWindow?
    @State private var focusSession = CalculatorFocusSession()
    @FocusState private var fieldFocused: Bool

    /// DEBUG gallery: a fixed input and no focus handling.
    var previewInput: String?

    var body: some View {
        let outcome = evaluate(input)
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            header
            field
            resultLine(outcome)
            historyList
        }
        .nookWidgetFrame()
        .background(CalculatorWindowReader(window: $window))
        .onAppear {
            if let previewInput { input = previewInput; return }
            #if DEBUG
            CalculatorDebug.install()
            #endif
            if case .result(let r) = outcome, r.usesCurrency { rates.refreshIfNeeded() }
            if settings.focusOnOpen { focusSoon() }
        }
        .onDisappear {
            guard previewInput == nil else { return }
            focusSession.restorePreviousApp()
        }
        .onChange(of: input) { _, new in
            if new.range(of: #"[A-Za-z]{3}|[$€£¥]"#, options: .regularExpression) != nil { rates.refreshIfNeeded() }
        }
        .onHover { inside in
            // an empty focused field must not hold the notch open once the pointer leaves
            guard !inside, previewInput == nil, fieldFocused,
                  input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            fieldFocused = false
            window?.makeFirstResponder(nil)
            focusSession.restorePreviousApp()
        }
        .background {
            // ⌘K: focus the field (works while the notch window is key)
            Button("") { focusNow() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .nookWidgetGalleryHook()
    }

    // MARK: Parts

    private var header: some View {
        NookWidgetHeader("Calculator", systemImage: "function") {
            if rates.isFetching {
                ProgressView().controlSize(.mini)
            }
            if !history.items.isEmpty {
                NookClearHistoryButton(help: String(localized: "Clear calculator history")) { history.clear() }
            }
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "equal.circle.fill")
                .font(.subheadline)
                .foregroundStyle(fieldFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            TextField("12 km in mi, 100 usd in jpy…", text: $input)
                .textFieldStyle(.plain)
                .font(.system(.subheadline, design: .monospaced))
                .focused($fieldFocused)
                .autocorrectionDisabled()
                .onSubmit(submit)
                .onExitCommand {
                    if input.isEmpty {
                        fieldFocused = false
                        window?.makeFirstResponder(nil)
                        focusSession.restorePreviousApp()
                    } else {
                        input = ""
                    }
                }
                .accessibilityLabel(Text("Calculator input"))
            if !input.isEmpty {
                Button {
                    input = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Clear"))
            }
        }
        .nookFieldChrome(focused: fieldFocused)
        .onTapGesture { focusNow() }
    }

    @ViewBuilder
    private func resultLine(_ outcome: CalculatorOutcome) -> some View {
        switch outcome {
        case .empty:
            Text(rates.table == nil && rates.lastError != nil
                 ? String(localized: "Currency rates unavailable (offline)")
                 : String(localized: "Type a calculation or a conversion"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .padding(.horizontal, 2)
        case .error(let message):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 2)
            .accessibilityElement(children: .combine)
        case .result(let r):
            Button {
                copy(r.display, id: "result", expression: input, number: r.number)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(r.display)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .textSelection(.disabled)
                        Spacer(minLength: 0)
                        Image(systemName: copiedID == "result" ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(copiedID == "result" ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                    }
                    Text(detailText(r))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .contentShape(Rectangle())
                .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius, highlighted: copiedID == "result")
            }
            .buttonStyle(.plain)
            .help(String(localized: "Click to copy"))
            .accessibilityLabel(Text(r.display))
            .accessibilityHint(Text("Click to copy"))
        }
    }

    private func detailText(_ r: CalculatorResult) -> String {
        var parts: [String] = []
        if let d = r.detail { parts.append(d) }
        if r.usesCurrency, rates.isStale, rates.table != nil, !rates.isFetching {
            parts.append(String(localized: "cached rates"))
        }
        return parts.isEmpty ? String(localized: "Click to copy") : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var historyList: some View {
        if history.items.isEmpty {
            Text("Press Return to keep a result here.")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(history.items) { item in
                        CalculatorHistoryRow(
                            item: item,
                            copied: copiedID == item.id.uuidString,
                            onCopy: { copy(item.result, id: item.id.uuidString, expression: nil, number: nil) },
                            onReuse: { input = item.expression; focusNow() },
                            onDelete: { withAnimation(.easeInOut(duration: 0.2)) { history.delete(item) } }
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Actions

    private func evaluate(_ text: String) -> CalculatorOutcome {
        var context = CalculatorContext()
        context.rates = rates.table
        context.decimalDigits = settings.decimalDigits
        context.defaultSourceCurrency = settings.fromCurrency
        context.defaultTargetCurrency = settings.toCurrency
        // the latest result that has a number (a time-zone answer at the top has none)
        context.ans = history.items.first(where: { $0.number != nil })?.number
        return CalculatorEngine.evaluate(text, context: context)
    }

    private func submit() {
        defer { fieldFocused = true }
        guard case .result(let r) = evaluate(input) else { NSSound.beep(); return }
        withAnimation(.easeInOut(duration: 0.2)) {
            history.add(expression: input, result: r.display, number: r.number)
        }
        clearInputIfItUsesAns()
    }

    /// After a result that used `ans` is committed, `ans` is that result, so the same line would show
    /// a different value at once ("ans * 2": 10, then 20). Clear it instead.
    private func clearInputIfItUsesAns() {
        if input.range(of: #"(?<![A-Za-z_])ans(?![A-Za-z0-9_])"#, options: [.regularExpression, .caseInsensitive]) != nil {
            input = ""
        }
    }

    /// Copies `text`; copying the live result also keeps it in the history.
    private func copy(_ text: String, id: String, expression: String?, number: Double?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if let expression {
            withAnimation(.easeInOut(duration: 0.2)) { history.add(expression: expression, result: text, number: number) }
            clearInputIfItUsesAns()
        }
        withAnimation(.easeInOut(duration: 0.15)) { copiedID = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == id { withAnimation { copiedID = nil } }
        }
    }

    private func focusSoon() {
        // the notch window is attached a moment after the content mounts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focusNow() }
    }

    private func focusNow() {
        guard previewInput == nil else { return }
        guard let window = window ?? NSApp.windows.first(where: { ($0 as? BetterWindow)?.isNotchWindow == true && $0.isVisible }) else { return }
        focusSession.activate(window)
        fieldFocused = true
    }
}

/// Remembers the app that was in front when the field took the keyboard, and gives it back.
@MainActor
final class CalculatorFocusSession {
    private var previousApp: NSRunningApplication?

    func activate(_ window: NSWindow) {
        if !NSApp.isActive {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
            NSApp.activate()
        }
        window.makeKey()
    }

    func restorePreviousApp() {
        guard let app = previousApp else { return }
        previousApp = nil
        // only if we still have the keyboard (the user may have switched apps meanwhile)
        if NSApp.isActive { app.activate() }
    }
}

private struct CalculatorHistoryRow: View {
    let item: CalculatorHistoryItem
    let copied: Bool
    let onCopy: () -> Void
    let onReuse: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 6) {
                Text(item.expression)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
                Spacer(minLength: 4)
                Text(item.result)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .layoutPriority(1)
                if copied {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
            .nookListRowBackground(highlighted: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(localized: "Click to copy"))
        .contextMenu {
            Button("Copy Result", action: onCopy)
            Button("Use Expression", action: onReuse)
            Divider()
            Button("Remove", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Click to copy"))
    }
}

/// Reads the hosting window (the notch window) of the widget.
private struct CalculatorWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let v = ReaderView()
        v.onWindow = { w in DispatchQueue.main.async { if window !== w { window = w } } }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
