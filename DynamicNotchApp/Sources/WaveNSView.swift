import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import CoreGraphics
import QuartzCore

// Audio visualization NSView subclass that draws wave lines using
//   CAShapeLayer pairs (one stroke + one fill per line), animates control
//   points randomly when isPlaying, with CABasicAnimation path morphing
class WaveNSView: NSView {

    // MARK: - MiddlePoint

    // Stores the random position and two bezier direction points for one wave line
    struct MiddlePoint {
        var point: CGPoint
        var direction1: CGPoint
        var direction2: CGPoint

        // Default initializer with zero values
        init() {
            self.point = .zero
            self.direction1 = .zero
            self.direction2 = .zero
        }

        // memberwise init used by updateMiddlePoints
        init(point: CGPoint, direction1: CGPoint, direction2: CGPoint) {
            self.point = point
            self.direction1 = direction1
            self.direction2 = direction2
        }
    }

    // MARK: - Properties

    //   Multiplier applied to wave amplitude
    var volume: Double = 1.0

    //   Color used for wave stroke lines, darkened per line tier
    var color: NSColor = .white

    //   When true, random movement starts; when false, timer stops
    var isPlaying: Bool = false {
        didSet {
            if isPlaying {
                // If isPlaying == true → startRandomMovement()
                startRandomMovement()
            } else {
                // If isPlaying == false → stopRandomMovement()
                stopRandomMovement()
            }
        }
    }

    //   Repeating timer that drives randomizeMovement() when isPlaying
    private var movementTimer: Timer? = nil

    //   Applied as layer filter for visual blur effect
    var blurFilter: CIFilter!

    //   Lazy backing storage for shapeLayers computed property
    private var _shapeLayersStorage: [[CAShapeLayer]]? = nil

    //   Guards against re-entrancy during cleanup/deinit
    private var isBeingDeallocated: Bool = false

    //   Array of MiddlePoint structs, one per wave line; initialized with linesCount in init
    var middlePoints: [MiddlePoint] = []

    // MARK: - Lazy shapeLayers

    // Created on first access (createShapeLayers()) and cached.
    var shapeLayers: [[CAShapeLayer]] {
        // If lazy storage is nil, create layers and cache
        if let cached = _shapeLayersStorage {
            return cached
        }
        let layers = createShapeLayers()
        _shapeLayersStorage = layers
        return layers
    }

    // MARK: - Initializers

    // One wave line per `linesCount`; sets up the blur filter and the backing layer.
    init(frame: CGRect, linesCount: Int) {
        super.init(frame: frame)

        // Gaussian blur applied to the whole layer
        guard let filter = CIFilter(name: "CIGaussianBlur") else {
            fatalError("CIGaussianBlur filter not available")
        }
        self.blurFilter = filter

        // one zeroed MiddlePoint per line
        if linesCount > 0 {
            self.middlePoints = Array(repeating: MiddlePoint(), count: linesCount)
        }

        setupLayer()
    }

    // Default frame init with linesCount=0
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    // Standard coder init chaining
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Layer Setup

    // Layer-backed view with the blur filter on its layer (scalingFilter 0).
    func setupLayer() {
        wantsLayer = true

        let backingLayer = CALayer()
        self.layer = backingLayer

        blurFilter.name = "blur"

        if let layer = self.layer {
            layer.filters = [blurFilter]

            layer.setValue(0, forKeyPath: "minificationFilter")
        }
    }

    // MARK: - Shape Layer Creation

    //   For each middlePoint (iterating in reverse, index descending):
    //     darkening = Double(index) * 0.2
    //     Creates 2 CAShapeLayer per line (stroke layer + fill layer)
    //     Each layer:
    //       strokeColor = color.darkened(by: darkening)
    //       fillColor = NSColor.clearColor
    //       name = String(index)
    //       zPosition = Double(middlePoints.count + index) (negated for reverse order)
    //       Added as sublayer of view's layer
    //     Appends [strokeLayer, fillLayer] pair to result array
    //   Returns [[CAShapeLayer]] (array of pairs)
    func createShapeLayers() -> [[CAShapeLayer]] {
        let count = middlePoints.count
        var result: [[CAShapeLayer]] = []

        //   So iteration goes: index 0 → count-1, 1 → count-2, ..., count-1 → 0
        //   darkening = Double(index) * 0.2
        for idx in 0..<count {
            let darkening = Double(idx) * 0.2

            // First CAShapeLayer (stroke)
            let strokeLayer = CAShapeLayer()

            let darkenedColor = color.darkened(amount: darkening)
            strokeLayer.strokeColor = darkenedColor.cgColor

            strokeLayer.lineWidth = 1.0

            strokeLayer.fillColor = NSColor.clear.cgColor

            strokeLayer.name = "\(idx)"

            let zPosition = Double(count - idx)
            strokeLayer.zPosition = zPosition

            self.layer?.addSublayer(strokeLayer)

            // Second CAShapeLayer (fill)
            let fillLayer = CAShapeLayer()

            let darkenedColor2 = color.darkened(amount: darkening)
            fillLayer.strokeColor = darkenedColor2.cgColor

            fillLayer.lineWidth = 1.0

            fillLayer.fillColor = NSColor.clear.cgColor

            fillLayer.name = "\(idx)"

            fillLayer.zPosition = zPosition

            self.layer?.addSublayer(fillLayer)

            result.append([strokeLayer, fillLayer])
        }

        return result
    }

    // MARK: - Random Values

    //   X: random between bounds.minX + 8.0 and bounds.maxX - 8.0
    //   Y: random around bounds.midY, amplitude = bounds.height * 0.2 * 0.5 * volume
    //   Uses SystemRandomNumberGenerator for randomness
    func generateRandomXY() -> (CGFloat, CGFloat) {
        let bounds = self.bounds

        let minX = bounds.minX + 8.0
        let maxX = bounds.maxX - 8.0

        let midY = bounds.midY

        let amplitude = bounds.height * 0.2 * 0.5 * CGFloat(volume)
        let minY = midY - amplitude
        let maxY = midY + amplitude

        let randomX = minX + (maxX - minX) * CGFloat.random(in: 0...1)

        let randomY = minY + (maxY - minY) * CGFloat.random(in: 0...1)

        return (randomX, randomY)
    }

    //   Generates two direction control points for bezier curve:
    //   - Random angle between -60° and +60° (cos <= 0.5 AND cos >= -0.5)
    //   - Random magnitude between 1.0 and 5.0
    //   - direction1 = (randomX - cos(angle) * magnitude, randomY + noise)
    //   - direction2 = (baseX + cos(angle) * magnitude, baseY + noise)
    func generateDirectionPoints(randomX: CGFloat, randomY: CGFloat) -> (CGPoint, CGPoint) {
        var angle: CGFloat
        repeat {
            angle = CGFloat.random(in: 0..<360) * .pi / 180.0
        } while cos(angle) > 0.5 || cos(angle) < -0.5

        let magnitude: CGFloat = CGFloat.random(in: 0...1) * 4.0 + 1.0

        let cosAngle = cos(angle)
        let sinAngle = sin(angle)

        let dir1X = randomX - abs(cosAngle) * magnitude

        //   direction1 is at the random point, direction2 uses calculated offset
        let dir1 = CGPoint(x: dir1X, y: randomY + sinAngle * magnitude * 0.5)

        let dir2 = CGPoint(x: randomX + abs(cosAngle) * magnitude * 0.5, y: randomY + sinAngle * magnitude * 0.5)

        return (dir1, dir2)
    }

    // Returns bounds midY plus random vertical jitter between -5.5 and +5.5
    func generateBaseY() -> CGFloat {
        let bounds = self.bounds
        let jitter = CGFloat.random(in: -5.5...5.5)
        return bounds.midY + jitter
    }

    // MARK: - Movement Animation

    //   For each middlePoint:
    //     1. generateRandomXY → random point
    //     2. generateDirectionPoints → two direction CGPoints
    //     3. generateBaseY → base Y for curve
    //     4. For each shapeLayer pair at this index:
    //        - Create CABasicAnimation on "path" keyPath
    //        - with kCAMediaTimingFunctionEaseInEaseOut
    //        - fromValue = presentationLayer path (if exists)
    //        - Create NSBezierPath:
    //            moveTo bounds.minX
    //            curveTo bounds.maxX, controlPoint1, controlPoint2
    //        - toValue = bezierPath.CGPath
    //        - Add animation for key "pathAnimation"
    //        - Set layer.path = toValue
    //     5. Update middlePoint in array with new values
    func randomizeMovement() {
        let count = middlePoints.count
        guard count > 0 else { return }

        let timingFuncName = CAMediaTimingFunctionName.easeInEaseOut

        for idx in 0..<count {
            let (randomX, randomY) = generateRandomXY()

            let (dir1, dir2) = generateDirectionPoints(randomX: randomX, randomY: randomY)

            let baseY = generateBaseY()

            let layers = shapeLayers
            guard idx < layers.count else { continue }

            let layerPair = layers[idx]

            let jitter = CGFloat.random(in: -5.5...5.5)

            for shapeLayer in layerPair {
                let animation = CABasicAnimation(keyPath: "path")

                animation.timingFunction = CAMediaTimingFunction(name: timingFuncName)

                animation.duration = 0.2

                if let presentationLayer = shapeLayer.presentation(),
                   let currentPath = presentationLayer.path {
                    animation.fromValue = currentPath
                }

                animation.isRemovedOnCompletion = true

                //   moveTo bounds.minX at midY
                //   curveTo bounds.maxX at (midY + jitter) with control points
                let bezierPath = NSBezierPath()
                let bounds = self.bounds

                bezierPath.move(to: CGPoint(x: bounds.minX, y: baseY))

                //   controlPoint1: dir1, controlPoint2: dir2)
                bezierPath.curve(
                    to: CGPoint(x: bounds.maxX, y: baseY + jitter),
                    controlPoint1: dir1,
                    controlPoint2: dir2
                )

                animation.toValue = bezierPath.cgPath

                shapeLayer.add(animation, forKey: "pathAnimation")

                shapeLayer.path = bezierPath.cgPath
            }

            //   stores randomXY, dir1, dir2
            if idx < middlePoints.count {
                let jitterValue = CGFloat.random(in: -5.5...5.5)
                middlePoints[idx] = MiddlePoint(
                    point: CGPoint(x: randomX, y: randomY),
                    direction1: dir1,
                    direction2: CGPoint(x: dir2.x, y: baseY + jitterValue)
                )
            }
        }
    }

    // MARK: - Color Update

    //   For each shapeLayer pair in shapeLayers:
    //     For each layer in pair:
    //       Parse layer.name as Int
    //       If valid number:
    //         darken = number * 0.1, shade = number * 0.2
    //         strokeColor = color.darkened(by: darken).shaded(by: shade)
    func updateLayerColors() {
        let layers = shapeLayers

        for pair in layers {
            for shapeLayer in pair {
                guard let nameStr = shapeLayer.name,
                      let indexInt = Int(nameStr) else { continue }

                let darkAmount = Double(indexInt) * 0.1

                let shadeAmount = Double(indexInt) * 0.2

                let darkened = color.darkened(amount: darkAmount)
                let shaded = darkened.shaded(amount: shadeAmount)
                shapeLayer.strokeColor = shaded.cgColor
            }
        }
    }

    // MARK: - Timer-based Movement

    //   If isPlaying:
    //     Stops existing timer (invalidate + nil out)
    //     Timer block calls randomizeMovement()
    //   Timer has weak self reference to avoid retain cycles
    func startRandomMovement() {
        guard isPlaying else { return }

        stopRandomMovement()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Timer callback calls randomizeMovement each tick
            self.randomizeMovement()
        }

        self.movementTimer = timer
    }

    // Inalidates and nils out movementTimer
    func stopRandomMovement() {
        movementTimer?.invalidate()
        movementTimer = nil
    }

    // Updates blurFilter amount based on Double parameter
    //   Called from parent context (WaveView) to adjust blur with volume changes
    func changeBlur(to value: Double) {
        // Set CIGaussianBlur inputRadius or similar parameter
        blurFilter?.setValue(value, forKey: kCIInputRadiusKey)
    }

    // MARK: - Cleanup


    // Stops the movement timer once (also from deinit).
    func cleanup() {
        guard !isBeingDeallocated else { return }

        isBeingDeallocated = true

        stopRandomMovement()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.movementTimer?.invalidate()
            self.movementTimer = nil
        }
    }

    // Deinit calls cleanup for safety
    deinit {
        cleanup()
    }
}
