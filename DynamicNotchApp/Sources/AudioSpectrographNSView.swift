import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import CoreGraphics
import QuartzCore

// 3-bar audio visualization NSView subclass with CAShapeLayer bars,
//   smooth interpolation between random target heights, CVDisplayLink-driven animation,
//   volume and color property controls
class AudioSpectrographNSView: NSView {

    // MARK: - Properties

    //   Multiplier applied to bar heights before rendering
    var volume: CGFloat = 1.0

    //   fillColor applied to each CAShapeLayer bar
    var color: NSColor = .white {
        didSet {
            // When color changes, update all bar layer fill colors
            for bar in bars {
                bar.fillColor = color.cgColor
            }
        }
    }

    //   3 CAShapeLayer instances created in setupLayers()
    var bars: [CAShapeLayer] = []

    //   Currently rendered bar heights, smoothly interpolated toward targets
    var currentHeights: [CGFloat] = [2.0, 2.0, 2.0]

    //   Desired bar heights, randomly assigned when isPlaying
    var targetHeights: [CGFloat] = [2.0, 2.0, 2.0]

    //   Tracks whether CVDisplayLink is currently running
    var animating: Bool = false

    //   Read from parent context — determines whether bars animate with random heights
    //   or collapse to minimum height 2.0
    var isPlaying: Bool = false

    //   Wraps CVDisplayLink for CADisplayLink-driven animation callbacks
    private var displayLinkHandler: DisplayLinkHandler?

    //   Guards against cleanup operations during deinit
    private var isBeingDeallocated: Bool = false

    // MARK: - Initializers

    //   Straightforward chaining with setup deferred to setupLayers()
    required init?(coder: NSCoder) {
        // super.init(coder: coder)
        super.init(coder: coder)
        // Calls setupLayers() after super init
        setupLayers()
    }

    override init(frame: NSRect) {
        // super.init(frame: frame)
        super.init(frame: frame)
        // Calls setupLayers() after super init
        setupLayers()
    }

    // MARK: - Layer Setup

    //   Creates 3 CAShapeLayer bars:
    //     For each: CAShapeLayer.init(), drawsAsynchronously=true, opaQue=true
    //     fillColor = self.color.cgColor
    //     Adds as sublayer of view's layer
    //     Appends to barLayers array
    //     Appends 2.0 to targetHeights and currentHeights
    //   Then calls updateTargetHeights(), interpolateHeights(), updateBarHeights()
    //   Runs on MainActor (via DispatchQueue.main.async)
    func setupLayers() {
        // Ensure runs on main thread (layer operations require main thread)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            for i in 0..<3 {
                let layer = CAShapeLayer()
                // drawsAsynchronously = true (offloads rendering to background)
                layer.drawsAsynchronously = true
                // isOpaque = true (no transparency blending needed for bars)
                layer.isOpaque = true
                // fillColor = self.color.cgColor
                layer.fillColor = self.color.cgColor

                // Add as sublayer of the view's backing layer
                self.wantsLayer = true
                self.layer?.addSublayer(layer)

                // Append to barLayers array
                self.bars.append(layer)

                // Append 2.0 to targetHeights and currentHeights (minimum bar height)
                self.targetHeights.append(2.0)
                self.currentHeights.append(2.0)
            }

            // Called at end of setupLayers:
            //   updateTargetHeights() → interpolateHeights() → updateBarHeights()
            self.updateTargetHeights()
            self.interpolateHeights()
            self.updateBarHeights()
        }
    }

    // MARK: - Bar Height Management

    //   Iterates 3 bars (indices 0, 1, 2)
    //   For each: smoothed = current[i] + (target[i] - current[i]) * 0.05
    //   If abs(current[i] - smoothed) < 0.02: snap current[i] = target[i]
    //   Else: current[i] = smoothed
    //   Called each display link frame to advance animation
    func interpolateHeights() {
        // Iterate 3 bars (indices 0, 1, 2)
        for i in 0..<3 {
            guard i < currentHeights.count, i < targetHeights.count else { continue }

            let current = currentHeights[i]
            let target = targetHeights[i]

            // smoothed = current + (target - current) * 0.05
            //   Linear interpolation with 5% step — produces smooth exponential ease
            let smoothed = current + (target - current) * 0.05

            // If abs(current - smoothed) < 0.02: snap to target
            //   Prevents infinite micro-adjustments when very close
            if abs(current - smoothed) < 0.02 {
                // Snap: current[i] = target[i]
                currentHeights[i] = target
            } else {
                // Normal step: current[i] = smoothed
                currentHeights[i] = smoothed
            }
        }
        // After interpolating, update the visual bars
        updateBarHeights()
    }

    //   Sets targetHeights[0...2] = 2.0 and currentHeights[0...2] = 2.0
    //   2.0 = minimum bar height in points
    //   Dispatches updateBarHeights on main queue async (DispatchQueue.main.async)
    func resetBars() {
        // Set all target heights to minimum (2.0)
        for i in 0..<min(3, targetHeights.count) {
            targetHeights[i] = 2.0
        }
        // Set all current heights to minimum (2.0)
        for i in 0..<min(3, currentHeights.count) {
            currentHeights[i] = 2.0
        }

        // Dispatch updateBarHeights on main queue async
        DispatchQueue.main.async { [weak self] in
            self?.updateBarHeights()
        }
    }

    // MARK: - Target Height Update

    //   Iterates 3 bars
    //   For each bar where abs(current[i] - target[i]) < 1.0 (nearly at target):
    //     If isPlaying: random target height between 2.0 and 16.0 (random % 14 + 2)

    //   Called each display link frame after interpolateHeights to assign new targets
    func updateTargetHeights() {
        // Iterate 3 bars
        for i in 0..<min(3, min(currentHeights.count, targetHeights.count)) {
            let current = currentHeights[i]
            let target = targetHeights[i]

            // Only assign new target when close to current target
            guard abs(current - target) < 1.0 else { continue }

            if isPlaying {
                // Random target height: range 2.0 ... 16.0
                //   Converted to CGFloat: 2.0 ... 15.0
                let randomHeight = CGFloat(Int.random(in: 2...15))
                targetHeights[i] = randomHeight
            } else {
                // Not playing: collapse to minimum height 2.0
                targetHeights[i] = 2.0
            }
        }
    }

    // MARK: - Visual Update (Rendering)

    //   Checks Thread.isMainThread
    //   On main thread:
    //     Compute width = bounds.width, totalWidth = width - 9.0
    //     startX = totalWidth * 0.5 (centers bars)
    //     For each of 3 bars:
    //       height = max(currentHeights[i] * volume, 2.0) (min height 2.0)
    //       x = startX + CGFloat(i) * 3.5
    //       y = (bounds.height - height) * 0.5
    //       NSBezierPath(roundedRect: ...) with cornerRadius = height * 0.5
    //       Set barLayers[i].path = bezierPath.cgPath
    //     If !isPlaying, check if all bars at 2.0 AND animating → stopAnimation()
    //   If not main thread: dispatch to DispatchQueue.main.async
    func updateBarHeights() {
        // Check Thread.isMainThread — layer path updates must be on main
        guard Thread.isMainThread else {
            // Re-dispatch to main queue if called from background
            DispatchQueue.main.async { [weak self] in
                self?.updateBarHeights()
            }
            return
        }

        // width = bounds.width
        let width = bounds.width
        // totalWidth = width - 9.0 (total spread of 3 bars)
        let totalWidth = width - 9.0
        // startX = totalWidth * 0.5 (centers the bar group horizontally)
        let startX = totalWidth * 0.5

        // Track whether all bars are at minimum (for auto-stop)
        var allBarsAtMinimum = true

        for i in 0..<min(3, bars.count) {
            let rawHeight = i < currentHeights.count ? currentHeights[i] * volume : 2.0
            // height = max(currentHeights[i] * volume, 2.0) — minimum 2.0pt
            let height = max(rawHeight, 2.0)

            // x = startX + CGFloat(i) * 3.5 (bars spaced 3.5pt apart)
            let x = startX + CGFloat(i) * 3.5
            // y = (bounds.height - height) * 0.5 (vertically centered)
            let y = (bounds.height - height) * 0.5

            // NSBezierPath roundedRect with cornerRadius = height * 0.5
            //   Creates pill-shaped bars (full-radius ends)
            let barRect = NSRect(x: x, y: y, width: 2.0, height: height)
            let bezierPath = NSBezierPath(
                roundedRect: barRect,
                xRadius: height * 0.5,
                yRadius: height * 0.5
            )

            // Set barLayers[i].path = bezierPath.cgPath
            bars[i].path = bezierPath.cgPath

            // Check if this bar is at minimum height
            if height > 2.0 + 0.01 {
                allBarsAtMinimum = false
            }
        }

        // If !isPlaying AND all bars at minimum AND animating: stopAnimation()
        if !isPlaying && allBarsAtMinimum && animating {
            stopAnimation()
        }
    }

    // MARK: - Animation Control

    //   Check displayLinkHandler exists
    //   If CVDisplayLink not running: set CACurrentMediaTime as anchor, call CVDisplayLinkStart
    //   Set animating = true
    //   The display link callback calls interpolateHeights() → updateTargetHeights() each frame
    func startAnimation() {
        // Guard: displayLinkHandler must exist
        guard let handler = displayLinkHandler else {
            // If no handler exists, create one with the display link callback
            //   The callback chain: interpolateHeights() → updateTargetHeights()
            //   → each frame updates bars toward random targets
            let newHandler = DisplayLinkHandler()
            newHandler.callback = { [weak self] in
                guard let self = self else { return }
                self.interpolateHeights()
                self.updateTargetHeights()
            }
            displayLinkHandler = newHandler

            // CVDisplayLink starts from current media time for smooth scheduling
            newHandler.start()

            // Set animating = true
            animating = true
            return
        }

        // If CVDisplayLink is not running, start it
        if !handler.isRunning {
            handler.start()
        }

        // Set animating = true
        animating = true
    }

    //   If displayLinkHandler exists and CVDisplayLink is running: call CVDisplayLinkStop
    //   Set animating = false
    //   Call resetBars() to collapse all bars to minimum
    func stopAnimation() {
        // Check displayLinkHandler exists and is running
        if let handler = displayLinkHandler, handler.isRunning {
            handler.stop()
        }

        // Set animating = false
        animating = false

        // Call resetBars() to collapse bars to minimum height
        resetBars()
    }

    // MARK: - Cleanup

    //   If not being deallocated:
    //     Call stopAnimation()
    //     Dispatch on main async: remove all bar layers from superlayer,
    //       nil out barLayers/currentHeights/targetHeights
    //   The isBeingDeallocated guard prevents double-cleanup during deinit
    func cleanup() {
        // Guard against double-cleanup during deallocation
        guard !isBeingDeallocated else { return }

        // Set flag to prevent re-entrancy
        isBeingDeallocated = true

        // Stop animation and display link
        stopAnimation()

        // Dispatch on main async: remove layers, nil out arrays
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Remove each bar layer from its superlayer
            for bar in self.bars {
                bar.removeFromSuperlayer()
            }

            // Nil out arrays to release memory
            self.bars.removeAll()
            self.currentHeights.removeAll()
            self.targetHeights.removeAll()
        }
    }

    // Deinit calls cleanup for safety
    deinit {
        cleanup()
    }
}
