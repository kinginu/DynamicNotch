// Shared layout pieces of the Nook widgets (refactor R13, 2026-10-20). Builds on
// Support/NookWidgetChrome.swift (metrics, `nookGlass`, `nookCard`, buttons, chips, empty state);
// this file adds what the widget views used to repeat inline:
//   - `nookWidgetFrame()`: the widget's inner padding + fill-the-cell frame;
//   - `nookFieldChrome(focused:)`: the quinary text-field well with the accent focus ring
//     (Calculator input, Reminders' "New reminder…");
//   - `nookListRowBackground(highlighted:separatorInset:)`: hover / highlight fill of plain list
//     rows with an optional hairline separator (Clipboard, Reminders, Calculator history);
//   - `NookIconBadge`: the SF Symbol in a circle that leads device rows (Batteries, Bluetooth,
//     Audio), accent-filled when active;
//   - `NookAlertBell`: the ringing bell of the Timer / Focus end alerts.
import SwiftUI

extension NookWidgetMetrics {
    /// Spacing between the stacked parts of most widgets (header, content, footer).
    static let stackSpacing: CGFloat = 6
    /// Corner radius of the hover / highlight fill of plain list rows.
    static let listRowCornerRadius: CGFloat = 6
}

extension View {
    /// The widget's inner padding, then fill the grid cell (content pinned to `alignment`).
    func nookWidgetFrame(alignment: Alignment = .top) -> some View {
        padding(NookWidgetMetrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// Text-field well: quinary rounded rectangle at the control height, accent ring while focused
    /// (like a focused macOS search field). Apply to the HStack holding the icon + plain field.
    func nookFieldChrome(focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous)
        return padding(.horizontal, 8)
            .frame(height: NookWidgetMetrics.controlHeight)
            .background(shape.fill(.quinary))
            .overlay { shape.strokeBorder(Color.accentColor.opacity(focused ? 0.8 : 0), lineWidth: 2) }
            .animation(.easeOut(duration: 0.15), value: focused)
            .contentShape(Rectangle())
    }

    /// Plain list row background: a quinary fill while `highlighted` (hovered / just copied) and,
    /// with a `separatorInset`, a hairline under the row starting that far from the leading edge.
    func nookListRowBackground(highlighted: Bool, separatorInset: CGFloat? = nil) -> some View {
        background(
            RoundedRectangle(cornerRadius: NookWidgetMetrics.listRowCornerRadius, style: .continuous)
                .fill(.quinary.opacity(highlighted ? 1 : 0))
        )
        .overlay(alignment: .bottom) {
            if let separatorInset {
                Rectangle().fill(.quinary).frame(height: 0.5).padding(.leading, separatorInset)
            }
        }
    }
}

/// Leading symbol of a device row: an SF Symbol (hierarchical) centred in a `diameter` circle —
/// white on the accent colour when `isActive` (default / connected), else primary on quaternary.
struct NookIconBadge: View {
    var systemImage: String
    var diameter: CGFloat
    var symbolSize: CGFloat
    var isActive: Bool = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: symbolSize, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
    }
}

/// Ringing bell of an "ended" state (Timer alert, Focus done): a wiggling `bell.fill` in `tint`
/// on a faint tinted circle of `diameter` (the symbol is half as tall).
struct NookAlertBell: View {
    var tint: Color
    var diameter: CGFloat

    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: diameter / 2, weight: .semibold))
            .foregroundStyle(tint)
            .symbolEffect(.wiggle, options: .repeating)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(tint.opacity(0.18)))
            .accessibilityHidden(true)
    }
}
