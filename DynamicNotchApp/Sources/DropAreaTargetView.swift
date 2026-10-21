import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// One drop target card of the open notch. Used for the Tray card while files are dragged over the notch and
//   for the AirDrop zone on the right of the tray (always, at the same place and size — see
//   TrayLayout). Rounded card with an icon, a title and a subtitle; dashed outline at rest, accent
//   fill + solid outline while a drag is over it (`isHovered`), a slightly stronger fill on pointer
//   hover. Publishes its frame for NotchViewModel.hoveredDropTargetID.
//   Restyle (2026-10-20): system fills (.quinary / .quaternary), accent colour, text styles — the
//   shared widget chrome (NookWidgetMetrics) instead of fixed white-with-opacity colours.
struct DropAreaTargetView: View {
    enum Icon {
        case symbol(String)
        /// the system AirDrop icon (NSSharingService), SF Symbol fallback
        case airDrop
    }

    var id: String
    var icon: Icon
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    /// a drag is over this target
    var isHovered: Bool
    /// the pointer (no drag) is over this target (clickable targets)
    var isPointerHovered: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius + 4, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 6) {
            iconView
                .frame(width: 44, height: 44)
                .scaleEffect(isHovered ? 1.12 : 1.0)
            VStack(spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(NookWidgetMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            shape.fill(isHovered ? AnyShapeStyle(Color.accentColor.opacity(0.22))
                       : isPointerHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
        )
        .overlay(
            shape.strokeBorder(isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary),
                               style: StrokeStyle(lineWidth: isHovered ? 2 : 1.5,
                                                  dash: isHovered ? [] : [6, 4]))
        )
        .contentShape(shape)
        .animation(.snappy(duration: 0.2), value: isHovered)
        .animation(.snappy(duration: 0.15), value: isPointerHovered)
        .accessibilityElement(children: .combine)
        .dropAreaTarget(id)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        case .airDrop:
            if let image = Self.airDropImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// The AirDrop icon the system uses in share menus.
    private static let airDropImage: NSImage? = NSSharingService(named: .sendViaAirDrop)?.image
}
