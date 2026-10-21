import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import QuartzCore

// Manages CALayer-based rendering of native glass pill with slab geometry,
//   backdrop layers, highlight layers, SDF element layers, and element geometry application
class NativeGlassPillView {

    // Host layer for the pill (root layer)
    private var hostLayer: CALayer?

    // Array of glass element layers (one per slat)
    private var elementLayers: [CALayer] = []

    // Backdrop layer pair (background + shadow)
    private var backdropLayer: CALayer?
    private var backdropShadowLayer: CALayer?

    // Current host size for geometry calculations
    private var hostSize: CGSize = .zero

    // Current slat array
    private var currentSlabs: [GlassSlab] = []

    // MARK: - init()

    // Initializes with default values, no layers until layout() called
    init() {
        self.hostLayer = nil
        self.elementLayers = []
        self.backdropLayer = nil
        self.backdropShadowLayer = nil
    }

    // MARK: - applyElementGeometry

    // Applies slat geometry (position, size, rotation, corner radius) to a CALayer element
    func applyElementGeometry(_ layer: CALayer, slab: GlassSlab, hostSize: CGSize) {
        // Set frame from slat rect
        layer.frame = slab.rect

        // Apply corner radius from slat
        layer.cornerRadius = slab.cornerRadius

        // Apply opacity from slat
        layer.opacity = Float(slab.opacity)

        // Apply transform if slat has rotation
        if slab.rotation != 0 {
            layer.transform = CATransform3DMakeRotation(slab.rotation, 0, 0, 1)
        }

        // Apply shadow properties
        layer.shadowOpacity = Float(slab.shadowOpacity)
        layer.shadowOffset = slab.shadowOffset
        layer.shadowRadius = slab.shadowRadius
        if let shadowColor = slab.shadowColor {
            layer.shadowColor = shadowColor
        }
    }

    // MARK: - applyGlassBackgroundDefaults

    // Sets default glass background properties on an NSObject (typically NSView or CALayer)
    func applyGlassBackgroundDefaults(to object: NSObject) {
        // Configure for translucent glass appearance
        if let layer = object as? CALayer {
            layer.cornerRadius = 20
            layer.masksToBounds = true
            layer.cornerCurve = .continuous
        }
    }

    // MARK: - effectiveSlabs

    // effectiveSlabs(for:) -> [GlassSlab]
    // Filters and sorts slats for a given host size, returns visible/active slats
    func effectiveSlabs(for size: CGSize) -> [GlassSlab] {
        // Filter slats by visibility within bounds
        let visibleBounds = CGRect(origin: .zero, size: size)
        return currentSlabs.filter { slat in
            visibleBounds.intersects(slat.rect) && slat.opacity > 0
        }
    }

    // MARK: - makeBackdropLayer

    // makeBackdropLayer(size:sdfElementLayer:) -> (CALayer, CALayer)?
    // Creates backdrop (visual effect) and its shadow layer, composited with SDF element
    func makeBackdropLayer(size: CGSize, sdfElementLayer: CALayer) -> (CALayer, CALayer)? {
        // Create backdrop (blur/visual effect) layer
        let backdrop = CALayer()
        backdrop.frame = CGRect(origin: .zero, size: size)
        backdrop.masksToBounds = true

        // Add SDF element as sublayer
        backdrop.addSublayer(sdfElementLayer)

        // Create shadow layer
        let shadow = CALayer()
        shadow.frame = CGRect(origin: .zero, size: size)
        shadow.shadowOpacity = 0.15
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        shadow.shadowRadius = 8

        return (backdrop, shadow)
    }

    // MARK: - makeGlassHighlightLayer

    // makeGlassHighlightLayer(size:name:element:angle:color:) -> CALayer?
    // Creates a specular highlight layer for glass reflection effect
    func makeGlassHighlightLayer(
        size: CGSize,
        name: String,
        element: CALayer,
        angle: Double,
        color: CGColor
    ) -> CALayer? {
        // Gradient highlight layer at given angle
        let highlight = CAGradientLayer()
        highlight.frame = CGRect(origin: .zero, size: size)
        highlight.name = name

        // Linear gradient matching reflection angle
        highlight.type = .axial
        highlight.startPoint = CGPoint(x: 0.5 - cos(angle) * 0.3, y: 0.5 - sin(angle) * 0.3)
        highlight.endPoint = CGPoint(x: 0.5 + cos(angle) * 0.3, y: 0.5 + sin(angle) * 0.3)
        highlight.colors = [
            color.copy(alpha: 0.3)!,
            color.copy(alpha: 0.0)!
        ]

        // Mask to element shape
        highlight.mask = element

        return highlight
    }

    // MARK: - rebuildLayers

    // rebuildLayers(size:slabs:)
    // Destroys existing layers and rebuilds from slat array for new size
    func rebuildLayers(size: CGSize, slabs: [GlassSlab]) {
        // Remove old element layers
        elementLayers.forEach { $0.removeFromSuperlayer() }
        elementLayers.removeAll()

        // Store current state
        hostSize = size
        currentSlabs = slabs

        // Rebuild backdrop
        let sdfElement = CALayer()
        sdfElement.frame = CGRect(origin: .zero, size: size)
        if let (backdrop, shadow) = makeBackdropLayer(size: size, sdfElementLayer: sdfElement) {
            backdropLayer = backdrop
            backdropShadowLayer = shadow
        }

        // Create element layers for each slat
        for slab in slabs {
            let element = CALayer()
            applyElementGeometry(element, slab: slab, hostSize: size)
            elementLayers.append(element)
        }

        // Add all layers to host
        if let host = hostLayer {
            if let shadow = backdropShadowLayer {
                host.addSublayer(shadow)
            }
            if let back = backdropLayer {
                host.addSublayer(back)
            }
            for element in elementLayers {
                host.addSublayer(element)
            }
        }
    }

    // MARK: - updateGeometry

    // updateGeometry(size:slabs:)
    // Updates existing layer geometries without full rebuild
    func updateGeometry(size: CGSize, slabs: [GlassSlab]) {
        hostSize = size
        currentSlabs = slabs

        // Update each element layer geometry
        for (index, slab) in slabs.enumerated() {
            guard index < elementLayers.count else { break }
            applyElementGeometry(elementLayers[index], slab: slab, hostSize: size)
        }
    }

    // MARK: - layout()

    // layout()
    // Triggers a relayout pass — calls rebuildLayers if size changed, else updateGeometry
    func layout() {
        // If no host layer or size mismatch, rebuild
        if hostLayer == nil {
            rebuildLayers(size: hostSize, slabs: currentSlabs)
        } else {
            updateGeometry(size: hostSize, slabs: currentSlabs)
        }
    }

    // Attach to a host layer
    func attch(to layer: CALayer, size: CGSize) {
        hostLayer = layer
        hostSize = size
        layout()
    }
}

// MARK: - NativeGlassPillView.BuiltTree

// Tree structure for built glass layers
struct BuiltTree {
    // Root layer node
    var rootLayer: CALayer?

    // Child elements
    var elements: [CALayer] = []

    // Backdrop layers
    var backdrops: [CALayer] = []
}