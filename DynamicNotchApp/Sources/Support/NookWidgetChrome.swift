// Shared look of the Nook widgets (widget restyle pass, 2026-10-20).
//
// User decision: the widgets should look like first-party macOS UI. Everything here uses system
// styles so it adapts to the appearance:
//   - hierarchical foreground styles (.primary / .secondary / .tertiary) instead of fixed
//     white-with-opacity colours (the widget row forces a dark colour scheme inside the notch, but
//     nothing breaks in light mode);
//   - fills: `.quinary` / `.quaternary` shape styles for cards, rows and fields;
//   - controls: Liquid Glass on macOS 26 (`glassEffect`, `.buttonStyle(.glass)`), standard
//     `.bordered` / `.borderedProminent` and `.ultraThinMaterial` on macOS 14–15;
//   - HIG spacing 4 / 8 / 12 and system text styles (macOS has no Dynamic Type, but text styles
//     follow the system size settings; fixed 50 pt grid cells get line limits + scale factors).
import SwiftUI
import AppKit

enum NookWidgetMetrics {
    /// Inner padding of a widget inside its grid cell.
    static let padding: CGFloat = 8
    /// Standard spacing between the parts of a widget.
    static let spacing: CGFloat = 8
    /// Corner radius of cards / editors / artwork in a widget.
    static let cornerRadius: CGFloat = 12
    /// Corner radius of rows, fields and chips.
    static let rowCornerRadius: CGFloat = 8
    /// Height of a compact control row (fields, chips).
    static let controlHeight: CGFloat = 26
}

/// Whether the widgets use Liquid Glass (macOS 26). DEBUG: the offscreen widget gallery and
/// `DN_DEBUG_NOGLASS=1` switch to the macOS 14/15 material fallback, because glass layers are not
/// captured by `cacheDisplay` (glass controls come out invisible or white in snapshots).
enum NookGlass {
    #if DEBUG
    nonisolated(unsafe) static var forceFallback = ProcessInfo.processInfo.environment["DN_DEBUG_NOGLASS"] == "1"
    #else
    static let forceFallback = false
    #endif
}

extension View {
    /// Liquid Glass (macOS 26) in `shape`, else an ultra-thin material. `tint` colours the glass
    /// (prominent controls), `interactive` adds the press/hover response of glass buttons.
    @ViewBuilder
    func nookGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *), !NookGlass.forceFallback {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.85)) }
                }
            }
        }
    }

    /// Subtle card fill used behind editors, fields and list rows.
    func nookCard(cornerRadius: CGFloat = NookWidgetMetrics.cornerRadius, highlighted: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(highlighted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
        )
    }

    /// Glass button style on macOS 26 (`.glass` / `.glassProminent`), else `.bordered` /
    /// `.borderedProminent`.
    @ViewBuilder
    func nookButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *), !NookGlass.forceFallback {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}

/// Round icon-only button (SF Symbol) with a glass / material background. `prominent` tints it
/// with the accent colour (e.g. the timer's play button).
struct NookRoundIconButton: View {
    var systemImage: String
    var label: Text
    var diameter: CGFloat = 24
    var prominent: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .nookGlass(in: Circle(), tint: prominent ? .accentColor : nil, interactive: true)
                .overlay {
                    if #available(macOS 26, *), !NookGlass.forceFallback {
                        // glass buttons respond to hover/press themselves
                    } else {
                        Circle().fill(.primary.opacity(hovering ? 0.1 : 0))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Small capsule chip (presets, filters). Glass on macOS 26, material elsewhere.
struct NookChip<Label: View>: View {
    var isSelected: Bool = false
    /// Horizontal padding of the label (narrow rows use less).
    var horizontalPadding: CGFloat = 8
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: 26, maxWidth: .infinity, minHeight: 22)
                .contentShape(Capsule())
                .nookGlass(in: Capsule(), tint: isSelected ? .accentColor : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

/// Centered placeholder (SF Symbol, message, optional action) for empty widget states.
struct NookWidgetEmptyState: View {
    var systemImage: String
    var title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2.weight(.regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .nookButtonStyle()
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, NookWidgetMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
