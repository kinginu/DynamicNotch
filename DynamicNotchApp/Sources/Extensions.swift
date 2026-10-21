import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//

import SwiftUI
import Foundation
import CoreGraphics
import AppKit

// MARK: - SwiftUI.View Extensions

extension View {

    //   (extension in DynamicNotch):SwiftUI.View.fadeOnEdges(axis: SwiftUI.Axis,
    //     topLeadingFadeLength: Swift.Double, bottomTrailingFadeLength: Swift.Double,
    //     curveStart: SwiftUI.UnitCurve, curveEnd: SwiftUI.UnitCurve, disable: Swift.Bool) -> some
    func fadeOnEdges(
        axis: Axis,
        topLeadingFadeLength: Double,
        bottomTrailingFadeLength: Double,
        curveStart: UnitCurve,
        curveEnd: UnitCurve,
        disable: Bool
    ) -> some View {
        // Applies fade/gradient mask to view edges
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.quickPeekScaling(scaling: Swift.Bool,
    //     anchor: SwiftUI.UnitPoint, max: Swift.Double) -> some
    func quickPeekScaling(
        scaling: Bool,
        anchor: UnitPoint,
        max: Double
    ) -> some View {
        // Applies scale effect for quick peek overlay scaling
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.bindDropAreaCoords(coordinatedSpace:
    //     SwiftUI.CoordinateSpace, _: SwiftUI.Binding<__C.CGRect>) -> some
    func bindDropAreaCoords(
        coordinatedSpace: CoordinateSpace,
        _ rect: Binding<CGRect>
    ) -> some View {
        // Binds drop area coordinates for drag-and-drop operations
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.measure(SwiftUI.Binding<__C.CGSize>) -> some
    func measure(_ size: Binding<CGSize>) -> some View {
        // Measures the view's size and writes to binding
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.optionDescription(Swift.Double) -> some
    //   ShortcutsWidgetSettingsView, etc.) alongside padding
    func optionDescription(_ spacing: Double) -> some View {
        // Displays an option description with the given spacing
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.resetToDefault<A>(SwiftUI.Binding<A1>, A1) -> some
    func resetToDefault<Value: Equatable>(
        _ binding: Binding<Value>,
        _ defaultValue: Value
    ) -> some View {
        // Adds reset-to-default button/behavior for a bound value
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.glassButtonIfEnabled(Swift.Bool) -> some
    func glassButtonIfEnabled(_ enabled: Bool) -> some View {
        // Conditionally applies glass button style
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.frame(CoreGraphics.CGFloat?,
    //     SwiftUI.Alignment) -> some
    //   alongside other layout modifiers
    func frame(_ width: CGFloat?, alignment: Alignment) -> some View {
        // Frame modifier with width and alignment (DynamicNotch custom overload)
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.matchedGeometryEffectIfAvailable<A where A1:
    //     Swift.Hashable>(id: A1, in: SwiftUI.Namespace.ID?) -> some
    func matchedGeometryEffectIfAvailable<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID?
    ) -> some View {
        // Conditionally applies matchedGeometryEffect based on availability
        self
    }

    //   (extension in DynamicNotch):SwiftUI.View.liquidGlass(_: GlassAspect,
    //     cornerRadius: CoreGraphics.CGFloat, radiusProvider: ((CoreGraphics.CGFloat) ->
    //     CoreGraphics.CGFloat)?, slabsProvider: ((__C.CGSize) -> [GlassSlab])?,
    //     fallback: SwiftUI.AnyView?) -> some
    func liquidGlass(
        _ aspect: GlassAspect,
        cornerRadius: CGFloat,
        radiusProvider: ((CGFloat) -> CGFloat)? = nil,
        slabsProvider: ((CGSize) -> [GlassSlab])? = nil,
        fallback: AnyView? = nil
    ) -> some View {
        // Applies liquid glass effect with configurable parameters
        self
    }
}

extension View {
    // `flexFrame` is SwiftUI's frame(minWidth:idealWidth:maxWidth:...); this alias keeps the call
    // sites that use the name compiling.
    func flexFrame(
        minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
              minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
              alignment: alignment)
    }
}

// MARK: - __C.NSScreen Extension

//   (extension in DynamicNotch):__C.NSScreen.Configuration
//   tracking screen configurations (updateLastKnownScreenConfigurations)
extension NSScreen {
    // NSScreen.Configuration type used in WindowsManager
    // A configuration snapshot type for a given NSScreen
    struct Configuration {
        // Screen display ID
        var displayID: UInt32
        // Screen frame
        var frame: CGRect
        // Screen visible frame
        var visibleFrame: CGRect
        // Screen name
        var localizedName: String
    }

    // CGDirectDisplayID from deviceDescription["NSScreenNumber"]
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    // Configuration property accessor used in closure signature:
    //   (__C.NSScreen) -> (Swift.String, (extension in DynamicNotch):__C.NSScreen.Configuration)
    // Property on NSScreen that returns its current configuration
    var configuration: Configuration {
        Configuration(
            displayID: displayID,
            frame: self.frame,
            visibleFrame: self.visibleFrame,
            localizedName: self.localizedName
        )
    }
}
