import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//   using growingBubble(geometry:expansion:pose:forceDisableGlass:) with GeometryProxy
//   BubbleOutlineBoxShape clip, padding, and .liquidGlass modifier for slat rendering

import SwiftUI
import AppKit

struct LiquidGlassNotchBackground: Animatable, View {

    // Controls bubble expansion amount
    var expansion: CGFloat = 0.0

    // Animation pose value (0…1) for lerp along shape curve
    var pose: CGFloat = 0.0

    // When true, disables liquid glass rendering entirely
    var forceDisableGlass: Bool = false

    // geometry: BubbleGeometry — computed from NotchShape.resolve in growingBubble
    // Derived per-frame from footprimnt, nothSize, fineTuning, expansion
    var geometry: BubbleGeometry = BubbleGeometry()

    var animatableData: CGFloat {
        get { pose }
        set { pose = newValue }
    }

    // MARK: - Body

    // Clamps expansion to 1.0, draws Color.black (opacity computed from forceDisableGlass checks)
    // If forceDisableGlass true and !isDynamicNotch → default frame sizes 20x8
    // Calls growingBubble(geometry:expansion:pose:forceDisableGlass:) as GeometryReader content
    var body: some View {
        // Clamp expansion to 1.0 max
        let clampedExpansion = min(expansion, 1.0)

        GeometryReader { _ in
            growingBubble(
                geometry: geometry,
                expansion: clampedExpansion,
                pose: pose,
                forceDisableGlass: forceDisableGlass
            )
            .overlay(alignment: .center) {
                Color.black
                    .opacity(forceDisableGlass ? 0.85 : 0.0)
            }
        }
    }

    // MARK: - Growing bubble

    // growingBubble: constructs the animated glass bubble body
    // Called from body with GeometryProxy providing view dimensions
    func growingBubble(
        geometry: BubbleGeometry,
        expansion: CGFloat,
        pose: CGFloat,
        forceDisableGlass: Bool
    ) -> some View {
        // Creates the visual effect with glass layer
        glassLayer(geometry: geometry, pose: pose)
            .frame(
                width: forceDisableGlass ? 20 : nil,
                height: forceDisableGlass ? 8 : nil
            )
    }

    // MARK: - Glass layer helper

    // Gets LiquidGlassSettings params from Environment
    // Computes corerRadius via NotchShape.radius(forHeight:notchSize:isWidthFineTuning:)
    // Creates VisualEffectView with BubbleOutlineBoxShape clip + padding
    // Applies .liquidGlass(cornerRadius:radiusProvider:slabs:fallback:) modifier
    // Uses .liquidGlass modifier with LiquidGlassBackdrop content
    func glassLayer(geometry: BubbleGeometry, pose: CGFloat) -> some View {
        // Read LiquidGlassSettings from environment
        // LiquidGlassSettings.params has no aspect; use the default full-blur aspect
        let aspect: GlassAspect = .fullBlur

        // Compute corner radius from the notch footprint (see BubbleGeometry.cornerRadius)
        let radius = geometry.cornerRadius

        // VisualEffectView: visual effect material background with BubbleOutlineBoxShape clip
        return VisualEffectView(material: .hudWindow)
            .padding(.horizontal)
            .clipShape(BubbleOutlineBoxShape())

        // .liquidGlass takes the corner radius, a slab provider and a fallback view
            .liquidGlass(
                aspect,
                cornerRadius: radius,
                radiusProvider: nil,
                slabsProvider: { size in
                    // Slat closure returns [GlassSlab] array
                    geometry.slabs(for: size)
                },
                fallback: nil
            )
    }
}


// MARK: - BubbleGeometry

// The glass bubble footprint
//   around the notch and the slabs used by the .liquidGlass modifier.
struct BubbleGeometry: Equatable {
    // bubble footprint rect in the notch window's coordinate space
    var footprint: CGRect = .zero

    // notch corner radius (NotchShape default 14)
    var cornerRadius: CGFloat = 14.0

    init(footprint: CGRect = .zero, cornerRadius: CGFloat = 14.0) {
        self.footprint = footprint
        self.cornerRadius = cornerRadius
    }

    // one slab covering the whole host
    func slabs(for size: CGSize) -> [GlassSlab] {
        [GlassSlab(rect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius)]
    }

    // used by NotchView.beadCatchBand: blends the open amount by the hover factor,
    //   moving fully to `open` as `t` goes to 1
    static func bloomLerp(hover: CGFloat, open: CGFloat, _ t: CGFloat) -> CGFloat {
        let t = max(0, min(1, t))
        return open * (hover + (1 - hover) * t)
    }
}
