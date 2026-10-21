import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   2. Gets RichToolbarButtonConfiguration via .configuration(for: styleKind)
//   3. Gets configuration.label (button label view)
//        foregroundStyle = configuration's pressed color
//      Else:
//        foregroundStyle = Color.secondary
//   5. Chain applied to label:
//        .foregroundStyle(Color)
//        .font(environment font)
//        .frame(width:height:alignment:.center)
//          - width/height from RichToolbarButtonConfiguration.size
//        .background(Color) — color from configuration
//          - If material: .background(ShapeView<Rectangle>.fill(Material?))
//          - Otherwise: nil (handled by optional)
//        .clipShape(RoundedRectangle(cornerRadius: configuration.size, continuous))
//        .shadow(AnyShapeStyle, radius, x, y) — from configuration
//        .animation(.easeInOut(duration: 0.2), value: isPressed)
//
// ToolbarButtonStyle is a custom ButtonStyle for the notch toolbar.
//   It integrates with RichToolbarButtonConfiguration to apply consistent sizing,
//   colors, materials, and shadows based on the ToolbarButtonStyleKind.

import SwiftUI

struct ToolbarButtonStyle: ButtonStyle {

    // The kind of toolbar button determines configuration details
    var styleKind: ToolbarButtonStyleKind = .regular // default; call sites use ToolbarButtonStyle()

    // MARK: - makeBody

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        //   from the button configuration's internal representation.
        //   In Swift, this maps to the stored styleKind property.
        let kind = styleKind

        // RichToolbarButtonConfiguration.configuration(for: styleKind)
        //   Returns sizing, color, material, shadow info for the given style kind
        let toolbarConfig = ToolbarButtonMetrics(kind: kind) // RichToolbarButtonConfiguration (group D) is an empty stub; local metrics instead

        // Get configuration.label (the button label view)
        let label = configuration.label

        //   If pressed → use configuration's pressed color
        //   Else → use Color.secondary
        let isPressed = configuration.isPressed
        let foreColor: Color = isPressed
            ? toolbarConfig.pressedColor    // config provides pressed color
            : Color.secondary                // fallback Color.secondary

        // Chain: label.foregroundStyle(fgColor)
        //   .font(environment font)
        //   .frame(width:height:alignment:.center)
        //   .background(Color)
        //   .background(ShapeView<Rectangle>.fill(Material?))
        //   .clipShape(RoundedRectangle(cornerRadius: size, continuous))
        //   .shadow(AnyShapeStyle, ...)
        //   .animation(.easeInOut(duration: 0.2), value: isPressed)
        return label
            // foregroundStyle: pressed color or .secondary
            .foregroundStyle(foreColor)
            // font from environment
            .font(.system(size: 12))  // typical toolbar font size
            // frame with size from RichToolbarButtonConfiguration.size
            //   width/height from configuration size fields, alignment: center
            .frame(
                width: toolbarConfig.size.width,    // from config
                height: toolbarConfig.size.height,  // from config
                alignment: .center
            )
            // background(Color) — color from configuration
            .background(toolbarConfig.backgroundColor)
            // material background, if any
            .background {
                // Conditional: if toolbarConfig.material is non-nil
                if let material = toolbarConfig.material {
                    Rectangle()
                        .fill(material)  // Material fill
                }
            }
            // clipShape(RoundedRectangle(cornerRadius: configuration.size, type: .continuous))
            //   "size" here is the corner radius from config
            .clipShape(
                RoundedRectangle(
                    cornerRadius: toolbarConfig.cornerRadius,  // from config
                    style: .continuous
                )
            )
            // shadow from configuration
            .shadow(
                color: toolbarConfig.shadowColor,
                radius: toolbarConfig.shadowRadius,
                x: toolbarConfig.shadowOffset.x,
                y: toolbarConfig.shadowOffset.y
            )
            // animation(.easeInOut(duration: 0.2), value: isPressed)
            .animation(.easeInOut(duration: 0.2), value: isPressed)
    }
}

// Sizing / colour values of a toolbar button (RichToolbarButtonConfiguration).
private struct ToolbarButtonMetrics {
    var size: CGSize = CGSize(width: 24, height: 24)
    var pressedColor: Color = .primary
    var backgroundColor: Color = .clear
    var material: Material? = nil
    var cornerRadius: CGFloat = 6
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    var shadowOffset: CGPoint = .zero

    init(kind: ToolbarButtonStyleKind) {
        if kind == .prominent {
            backgroundColor = Color.primary.opacity(0.08)
            material = .thin
        }
    }
}
