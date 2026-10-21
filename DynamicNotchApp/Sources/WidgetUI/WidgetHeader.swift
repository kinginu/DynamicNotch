// Widget header (refactor R13, 2026-10-20): the "icon + title" label in secondary
// subheadline semibold that most Nook widgets put on top, with optional trailing accessories
// (a menu, a switch, a status, a Clear button) pushed to the right edge.
//
//   NookWidgetHeader("Storage", systemImage: "internaldrive")
//   NookWidgetHeader("Calculator", systemImage: "function") { ProgressView()…; NookClearHistoryButton(…) }
//
// Trailing views are laid out directly in the header's HStack (same spacing as before the
// refactor). Widgets whose header is a different kind of title (a list name in its colour, a month,
// a place name, a tinted phase) keep their own.
import SwiftUI

/// "icon + title" label of a widget header (also used for column titles, e.g. Audio's Output / Input).
struct NookWidgetHeaderLabel: View {
    var title: Text
    var systemImage: String

    init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.title = Text(titleKey)
        self.systemImage = systemImage
    }

    /// An already localized title.
    init(title: Text, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            title
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityAddTraits(.isHeader)
        .nookWidgetLiftHandle() // F9: press and hold the header label to lift the widget
    }
}

/// Header row: `NookWidgetHeaderLabel`, then the trailing accessories at the right edge.
struct NookWidgetHeader<Trailing: View>: View {
    var label: NookWidgetHeaderLabel
    var spacing: CGFloat
    @ViewBuilder var trailing: () -> Trailing

    init(_ titleKey: LocalizedStringKey, systemImage: String, spacing: CGFloat = 4,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = NookWidgetHeaderLabel(titleKey, systemImage: systemImage)
        self.spacing = spacing
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: spacing) {
            label
            Spacer(minLength: 4)
            trailing()
        }
    }
}

extension NookWidgetHeader where Trailing == EmptyView {
    init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.init(titleKey, systemImage: systemImage) { EmptyView() }
    }
}

/// "Clear" → "Clear All" (red, prominent) two-step button for a widget's history; the
/// confirmation disarms itself after 3 seconds. `action` runs inside an ease-in-out animation.
struct NookClearHistoryButton: View {
    /// Tooltip of the first step ("Clear clipboard history").
    var help: String
    var action: () -> Void

    @State private var confirming = false

    var body: some View {
        if confirming {
            Button("Clear All") {
                withAnimation(.easeInOut(duration: 0.2)) { action() }
                confirming = false
            }
            .controlSize(.mini)
            .nookButtonStyle(prominent: true)
            .tint(.red)
        } else {
            Button("Clear") {
                confirming = true
                // the confirmation disarms itself after a few seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirming = false }
            }
            .controlSize(.mini)
            .nookButtonStyle()
            .help(help)
        }
    }
}
