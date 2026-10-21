import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import CoreGraphics
import QuartzCore

// Visualizer that draws concentric circular rings with perlin-noise
//   displacement for an organic vibrating effect. Uses CVDisplayLink-driven
//   animation with 4 concentric CAShapeLayer rings at 30fps.
//   Each ring's path is recomputed each frame using PerlinNoiseGenerator
//   to offset control points along the circumference.
class VibratingCircleNSView: NSView {

    // MARK: - Properties

    var color: NSColor = .white

    var isPlaying: Bool = false

    private var displayLinkHandler: DisplayLinkHandler? = nil

    //   Records CACurrentMediaTime when animation started
    private var startTime: Double = 0.0

    private let updateInterval: Double = 0.0333

    private var lastUpdateTime: Double = 0.0

    var amplitude: CGFloat = 4.0

    var frequency: CGFloat = 2.0

    var blur: CGFloat = 0.15

    var velocity: CGFloat = 1.3

    var lineWidth: CGFloat = 0.8

    //   Created in init
    private var noisGenerator: PerlinNoiseGenerator!

    //   4 concentric circular ring layers
    private let layerCount: Int = 4

    private var layers: [CAShapeLayer] = []

    // MARK: - Initializers

    //   Layer-backed; sets up the rings and a 30 fps DisplayLinkHandler
    override init(frame: NSRect) {
        super.init(frame: frame)

        self.noisGenerator = PerlinNoiseGenerator()

        self.wantsLayer = true

        setupLayers()

        //   Closure calls updateLayers() each frame
        let handler = DisplayLinkHandler(target: self, fps: 30) { [weak self] in
            self?.updateLayers()
        }
        self.displayLinkHandler = handler
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Layer Setup

    //   Creates layerCount (4) CAShapeLayer rings:
    //     For each: CAShapeLayer.init(), fillColor = clear, strokeColor = self.color.cgColor
    //     lineWidth = self.lineWidth
    //     opacity = 0.7 - Double(i) * 0.15 (decreasing opacity per ring outward)
    //     Added as sublayer of view's layer
    //     Appended to layers array
    func setupLayers() {
        guard let viewLayer = self.layer else { return }

        for i in 0..<layerCount {
            let shapeLayer = CAShapeLayer()

            shapeLayer.fillColor = NSColor.clear.cgColor

            shapeLayer.strokeColor = color.cgColor

            shapeLayer.lineWidth = lineWidth

            //   0.7 - 0.15 * i → 0.7, 0.55, 0.4, 0.25
            shapeLayer.opacity = Float(0.7 - Double(i) * 0.15)

            viewLayer.addSublayer(shapeLayer)
            layers.append(shapeLayer)
        }
    }

    // MARK: - Path Generation

    //   Creates a CGPath that draws a deformed circle using perlin noise:
    //     - Divides circle into segments (8 per ring)
    //     - For each segment: computes angle step, adds perlin noise displacement
    //       to the radius based on time and position
    //     - noiseValue = noisGenerator.noise(x: cos(angle) * freq, y: sin(angle) * freq, time: elapsed * velocity)
    //     - displacedRadius = radius + noiseValue * amplitude
    //     - Uses addCurve for smooth bezier segments
    //   Returns CGPath for the deformed ring
    func createVibratingCirclePath(center: CGPoint, radius: CGFloat, layerIndex: Int) -> CGPath {
        let elapsed: Double
        if let handler = displayLinkHandler {
            elapsed = handler.elapsedTime ?? 0.0
        } else {
            elapsed = 0.0
        }

        let path = CGMutablePath()
        let segments = 8

        for i in 0..<segments {
            let angle = CGFloat(i) * (2.0 * .pi / CGFloat(segments))

            //   noiseX = cos(angle) * frequency, noiseY = sin(angle) * frequency
            let noiseX = cos(angle) * frequency
            let noiseY = sin(angle) * frequency

            let noiseValue = noisGenerator.noise(
                x: Double(noiseX),
                y: Double(noiseY),
                z: elapsed * Double(velocity)  // PerlinNoiseGenerator's third axis is `z`
            )

            //   Layer index adds step-out for concentric rings: radius *= (1.0 + 0.12 * layerIndex)
            let ringRadius = radius * (1.0 + CGFloat(layerIndex) * 0.12)
            let displacedRadius = ringRadius + CGFloat(noiseValue) * amplitude

            let x = center.x + cos(angle) * displacedRadius
            let y = center.y + sin(angle) * displacedRadius

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                //   Control points use tangent perpendicular to radius
                let prevAngle = CGFloat(i - 1) * (2.0 * .pi / CGFloat(segments))
                let cpAngle = (prevAngle + angle) * 0.5

                //   (standard circle bezier approximation constant)
                let cpOffset = ringRadius * 0.552284749831  // 4/3 * tan(pi/(2*segments))

                let cp1x = center.x + cos(prevAngle + (angle - prevAngle) * 0.25) * (ringRadius + cpOffset)
                let cp1y = center.y + sin(prevAngle + (angle - prevAngle) * 0.25) * (ringRadius + cpOffset)
                let cp2x = center.x + cos(angle - (angle - prevAngle) * 0.25) * (ringRadius + cpOffset)
                let cp2y = center.y + sin(angle - (angle - prevAngle) * 0.25) * (ringRadius + cpOffset)

                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: cp1x, y: cp1y),
                    control2: CGPoint(x: cp2x, y: cp2y)
                )
            }
        }

        path.closeSubpath()
        return path
    }

    // MARK: - Layer Update

    //   Throttles to updateInterval: checks elapsed time, skips if too soon
    //   For each layer (0..<layerCount):
    //     Computes path via createVibratingCirclePath centered on bounds.mid
    //     Sets layer.path = newPath
    //     Optionally adjusts layer blur filter
    func updateLayers() {
        let now = CACurrentMediaTime()
        guard now - lastUpdateTime >= updateInterval else { return }
        lastUpdateTime = now

        let bounds = self.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let baseRadius = min(bounds.width, bounds.height) * 0.5

        for i in 0..<min(layers.count, layerCount) {
            let path = createVibratingCirclePath(
                center: center,
                radius: baseRadius,
                layerIndex: i
            )
            layers[i].path = path
        }
    }

    // MARK: - Animation Control

    //   Resets startTime to CACurrentMediaTime, starts display link
    func startAnimating() {
        startTime = CACurrentMediaTime()
        lastUpdateTime = 0.0

        displayLinkHandler?.start()
    }

    //   Stops display link animation
    func stopAnimating() {
        displayLinkHandler?.stop()
    }

    // MARK: - Cleanup

    //   Stops display link, removes all layers from superlayer, nils arrays
    func cleanup() {
        stopAnimating()

        for layer in layers {
            layer.removeFromSuperlayer()
        }

        layers.removeAll()
        displayLinkHandler = nil
    }

    // Deinit calls cleanup
    deinit {
        cleanup()
    }
}
