// Empty / permission / notice states of the Nook widgets (refactor R13, 2026-10-20).
// `NookWidgetEmptyState` (Support/NookWidgetChrome.swift) stays the full-cell placeholder with an
// optional bordered action. This file adds the variants the widgets used to build inline:
//   - `NookWidgetAccessState`: "allow access" prompt — optional symbol, title, a prominent
//     "Allow Access" (first use) or plain "Open System Settings" button (Calendar, Reminders);
//   - `NookWidgetPlaceholder`: small centred symbol + line for an empty list below a header
//     ("No Reminders", "Nothing for today");
//   - `NookWidgetFootnote`: caption2 status / error line at the bottom of a widget.
import SwiftUI

/// Access prompt filling the rest of the widget: symbol (optional), title, one button.
struct NookWidgetAccessState: View {
    var systemImage: String? = nil
    var title: Text
    var actionTitle: LocalizedStringKey
    /// Accent-filled button (the first-use "Allow Access"); plain for "Open System Settings".
    var prominent: Bool
    var action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            title
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(actionTitle, action: action)
                .controlSize(.small)
                .nookButtonStyle(prominent: prominent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compact placeholder for an empty list under a header: symbol over one secondary line.
struct NookWidgetPlaceholder: View {
    var systemImage: String
    var title: Text

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            title
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One caption2 line at the bottom of a widget: a status (secondary, optional symbol) or an error (red).
struct NookWidgetFootnote: View {
    enum Tone { case secondary, error }

    var text: String
    var systemImage: String? = nil
    var tone: Tone = .secondary
    var lineLimit: Int = 1
    var minimumScaleFactor: CGFloat = 1

    var body: some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.caption2)
        .foregroundStyle(tone == .error ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
        .lineLimit(lineLimit)
        .truncationMode(.tail)
        .minimumScaleFactor(minimumScaleFactor)
    }
}
