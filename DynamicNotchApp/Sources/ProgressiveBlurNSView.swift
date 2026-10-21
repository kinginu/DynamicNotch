import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import CoreGraphics
import QuartzCore

// NSView subclass that applies a progressive blur effect using
//   private CAFilter/CABackdropLayer classes. Creates a ramp mask image
//   that controls blur intensity along one edge (top/bottom/left/right)
//   for smooth progressive blur transitions. Used in the Timer widget.

// MARK: - BlurEdge Enum

enum BlurEdge: UInt8 {
    case top = 0
    case bottom = 1
    case left = 2
    case right = 3
}

class ProgressiveBlurNSView: NSView {

    // MARK: - Properties

    var maxRadius: CGFloat = 12.0

    var edge: BlurEdge = .top

    var rampLength: CGFloat = 0.5

    var curveExponent: CGFloat = 1.6

    private var backdropLayer: CALayer? = nil

    private var blurFilter: NSObject? = nil

    // MARK: - Init

    // Defaults: maxRadius 12, edge .top, rampLength 0.5, curveExponent 1.6. Layer-backed,
    //   clipped to bounds; builds the backdrop right away.
    override init(frame: NSRect) {
        super.init(frame: frame)

        self.wantsLayer = true

        self.layer?.masksToBounds = true

        buildBackdrop()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.layer?.masksToBounds = true
        buildBackdrop()
    }

    // MARK: - Backdrop Construction

    //   Checks PrivateBlurClasses.backdrop and .filter static properties.
    //   If both available:
    //     1. Creates the backdrop layer (private CABackdropLayer class), anchor point (0, 0)
    //     2. Sets backdrop properties: usesOpaqueLayers=true, ignoresScrenClip=true,
    //        needsBottomContentGroup=true, scale=1
    //     3. Creates CAFilter with type "variableBlur"
    //     4. Sets filter properties: inputRadius=maxRadius, normalizedEdges=true,
    //        inputMaskImage (from ramp mask)
    //     5. Sets filters=[filter] on backdrop layer
    //     6. Adds backdropLayer as sublayer of self.layer
    func buildBackdrop() {
        guard let backdropClass = PrivateBlurClasses.backdrop,
              let filterClass = PrivateBlurClasses.filter else { return }

        guard let viewLayer = self.layer else { return }

        let backdrop = backdropClass.init()
        backdrop.anchorPoint = CGPoint.zero

        //   usesOpaqueLayers = true, ignoresScrenClip = true,
        //   needsBottomContentGroup = true, scale = 1
        backdrop.setValue(NSNumber(value: true), forKey: "usesOpaqueLayers")
        backdrop.setValue(NSNumber(value: true), forKey: "ignoresScreenClip")
        backdrop.setValue(NSNumber(value: true), forKey: "needsBottomContentGroup")
        backdrop.setValue(NSNumber(value: 1), forKey: "scale")

        guard let filter = filterClass.perform(
            Selector(("filterWithType:")),
            with: "variableBlur"
        ) else {
            return
        }

        // Dynamic cast to NSObject
        // perform(_:with:) returns Unmanaged<AnyObject>; unwrap before casting
        guard let filterObject = filter.takeUnretainedValue() as? NSObject else {
            return
        }

        //   inputRadius = maxRadius
        filterObject.setValue(NSNumber(value: maxRadius), forKey: "inputRadius")
        //   normalizedEdges = true
        filterObject.setValue(NSNumber(value: true), forKey: "normalizedEdges")

        backdrop.setValue([filterObject], forKey: "filters")

        viewLayer.addSublayer(backdrop)

        self.backdropLayer = backdrop
        self.blurFilter = filterObject
    }

    // MARK: - Layout

    //   Calls super.layout(). If backdropLayer and blurFilter exist:
    //     CATransaction.begin, setDisableActions(true)
    //     Set backdrop frame = bounds
    //     Update inputRadius on filter
    //     Create ramp mask image, set on filter as inputMaskImage
    //     CATransaction.commit
    override func layout() {
        super.layout()

        guard let backdrop = backdropLayer,
              let filter = blurFilter else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        backdrop.frame = self.bounds

        filter.setValue(NSNumber(value: maxRadius), forKey: "inputRadius")

        if let maskImage = makeRampMaskImage(size: self.bounds.size) {
            filter.setValue(maskImage, forKey: "inputMaskImage")
        }

        CATransaction.commit()
    }

    //   Generates a CGImage mask for progressive blur:
    //   1. Computes pixel dimensions: ceil(size.width) x ceil(size.height)
    //   2. Generates alpha ramp array based on edge direction:
    //      - Horizontal edges (top/bottom): vertical alpha ramp
    //      - Vertical edges (left/right): horizontal alpha ramp
    //   3. For each pixel distance along the ramp axis:
    //      alpha = pow(1.0 - clamp(distance/rampLength, 0, 1), curveExponent) * 255
    //   4. Creates RGBA bitmap from ramp, returns CGImage
    func makeRampMaskImage(size: CGSize) -> CGImage? {
        let clampedRamp = max(rampLength, 0.0001)

        let w = max(1, Int(ceil(size.width)))
        let h = max(1, Int(ceil(size.height)))

        let isHorizontal: Bool
        let pixelCount: Int

        switch edge {
        case .top, .bottom:
            isHorizontal = false
            pixelCount = h
        case .left, .right:
            isHorizontal = true
            pixelCount = w
        }

        var ramp = [UInt8](repeating: 0, count: pixelCount)

        let rampLen = max(2, pixelCount)
        for i in 0..<pixelCount {
            var t = CGFloat(i) / CGFloat(rampLen - 1)

            switch edge {
            case .bottom, .right:
                t = 1.0 - t
            default:
                break
            }

            let dist = 1.0 - t / clampedRamp
            if dist <= 0 {
                ramp[i] = 0
            } else {
                let alpha = pow(dist, curveExponent) * 255.0
                ramp[i] = UInt8(max(0, min(255, Int(alpha))))
            }
        }

        let bytesPerRow = w * 4
        let totalBytes = bytesPerRow * h
        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        if isHorizontal {
            // Left/right: each column gets ramp value, all rows same
            for row in 0..<h {
                let rowOffset = row * bytesPerRow
                for col in 0..<w {
                    let idx = rowOffset + col * 4
                    let rampIdx = min(col, pixelCount - 1)
                    let value = ramp[rampIdx]
                    pixelData[idx] = value
                    pixelData[idx + 1] = value
                    pixelData[idx + 2] = value
                    pixelData[idx + 3] = value
                }
            }
        } else {
            // Top/bottom: each row gets ramp value, all columns same
            for row in 0..<h {
                let rowOffset = row * bytesPerRow
                let rampIdx = min(row, pixelCount - 1)
                let value = ramp[rampIdx]
                for col in 0..<w {
                    let idx = rowOffset + col * 4
                    pixelData[idx] = value
                    pixelData[idx + 1] = value
                    pixelData[idx + 2] = value
                    pixelData[idx + 3] = value
                }
            }
        }

        guard let rgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelData,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: rgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        return context.makeImage()
    }
}

// Private backdrop/filter class cache (lazy loaded)
enum PrivateBlurClasses {
    static var backdrop: CALayer.Type? = {
        return NSClassFromString("CABackdropLayer") as? CALayer.Type
    }()

    static var filter: NSObject.Type? = {
        return NSClassFromString("CAFilter") as? NSObject.Type
    }()
}
