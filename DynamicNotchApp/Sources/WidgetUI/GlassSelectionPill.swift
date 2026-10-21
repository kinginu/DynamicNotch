// Glass selection pill of list rows (refactor R13, 2026-10-20), as in the Fan Control
// profile list: the selected row sits on a Liquid Glass capsule (ultra-thin material on the
// `NookGlass.forceFallback` / pre-26 path) with a faint white hairline; a hovered row gets a
// quinary capsule. Apply behind the row's content (after its padding / frame).
import SwiftUI

extension View {
    func nookSelectionPill(isSelected: Bool, hovering: Bool) -> some View {
        contentShape(Capsule())
            .background {
                if isSelected {
                    Color.clear
                        .nookGlass(in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                } else if hovering {
                    Capsule().fill(.quinary)
                }
            }
    }
}

/// Text style of a row title on the selection pill: white in dark mode (the notch), primary in
/// light mode; unselected rows are secondary.
enum NookSelectionTextStyle {
    static func style(isSelected: Bool, colorScheme: ColorScheme) -> AnyShapeStyle {
        guard isSelected else { return AnyShapeStyle(.secondary) }
        return colorScheme == .dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
    }
}
