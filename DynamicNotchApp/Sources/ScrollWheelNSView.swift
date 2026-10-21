import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI
import CoreGraphics

// Custom NSView subclass for scroll wheel gesture handling.
//   Tracks cumulative scroll deltas, smeaths them, computes velocity,
//   calls user-provided callbacks for drag changes, drag end, and click.
//   Uses NSEvent local monitor for scroll events and custom hit testing
//   via a SwiftUI Path resolved from a user-provided closure.
class ScrollWheelNSView: NSView {

    // MARK: - Drag Callbacks (external configuration)

    //   Signature: (CGSize cumulative, CGPoint smeathedDelta, CGSize smeathedVelocity) -> Void
    //   Called each scroll event during active drag
    var onDragChanged: ((CGSize, CGPoint, CGSize) -> Void)? = nil

    //   Signature: (CGSize cumulative, CGPoint smeathedDelta, CGSize smeathedVelocity) -> Void
    //   Called when drag ends (phase .ended or .cancelled)
    var onDragEnded: ((CGSize, CGPoint, CGSize) -> Void)? = nil

    //   Called when mouseUp occurs within 4pt of mouseDown point
    var onClick: (() -> Void)? = nil

    // MARK: - Mouse tracking state

    //   Recorded from mouseDown event; validity flag prevents re-triggering
    var mouseDownPoint: CGPoint = .zero

    //   Set to true in mouseDown, false after first mouseUp click check
    private var mouseDownPointIsValid: Bool = true

    //   Stored when scroll phase changes to .began; used for velocity calculation
    var initialScrollEvent: NSEvent? = nil

    // MARK: - Scroll tracking state

    //   Running total of scroll deltas since last .began
    var cumulativeTranslation: CGSize = .zero

    private let smeathingFactor: CGFloat = 0.3

    //   Exponentially smeathed scroll delta per event
    var smeathedScrollDelta: CGPoint = .zero

    //   Timestamp of previous scroll event for dt calculation
    private var lastEventTimestamp: Double = 0.0

    //   Exponentially smeathed scroll velocity
    var smeathedVelocity: CGSize = .zero

    private let velocitySmeathingFactor: CGFloat = 0.35

    // MARK: - Scroll monitor

    //   Local event monitor registered via NSEvent.addLocalMonitorForEventsMatchingMask
    private var scrollMonitor: Any? = nil

    // MARK: - Hit testing

    //   User-provided closure that returns a SwiftUI Path for hit testing
    var hitPathProvider: ((CGRect) -> Path)? = nil {
        didSet {
            //   On set, calls resolveHitPath() to update cached path
            resolveHitPath()
        }
    }

    //   Cached Path computed from hitPathProvider; used in hitTest for contains check
    private var resolvedHitPath: Path? = nil

    // MARK: - Initializers

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    // MARK: - Hit Path Resolution

    //   Calls hitPathProvider with self.bounds, stores result in resolvedHitPath
    func resolveHitPath() {
        if let provider = hitPathProvider {
            resolvedHitPath = provider(self.bounds)
        } else {
            resolvedHitPath = nil
        }
    }

    // MARK: - Hit Testing

    //   Calls super.hitTest first. If hit and resolvedHitPath is valid:
    //     Convert point to view coordinates (via superview conversion)
    //     Check if point is inside resolvedHitPath
    //     If inside: return self
    //     Else: return nil
    //   Otherwise: return super result
    override func hitTest(_ point: CGPoint) -> NSView? {
        let superResult = super.hitTest(point)

        guard let _ = superResult,
              let path = resolvedHitPath else {
            return superResult
        }

        let convertedPoint: CGPoint
        if let superview = self.superview {
            convertedPoint = self.convert(point, from: superview)
        } else {
            convertedPoint = point
        }

        if path.contains(convertedPoint, eoFill: false) {
            return self
        }

        return nil
    }

    // MARK: - Mouse Events

    //   If onClick exists AND mouseDownPoint is valid:
    //     Compute distance from mouseDownPoint to event.locationInWindow
    //     If hypot < 4.0: call onClick()
    //     Reset mouseDownPoint to .zero, mark invalid
    //   Else: call super.mouseUp
    override func mouseUp(with event: NSEvent) {
        if let clickHandler = onClick, mouseDownPointIsValid {
            let location = event.locationInWindow

            let dx = location.x - mouseDownPoint.x
            let dy = location.y - mouseDownPoint.y
            let distance = hypot(dx, dy)

            mouseDownPoint = .zero
            mouseDownPointIsValid = false

            if distance < 4.0 {
                clickHandler()
            }
        } else {
            super.mouseUp(with: event)
        }
    }

    // mouseDown(with:) — sets mouseDownPoint and validity flag
    //   Mouse-down location is captured for click detection in mouseUp
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        mouseDownPointIsValid = true
        super.mouseDown(with: event)
    }

    // MARK: - Scroll Event Handling

    //   Handles NSEventPhase:
    //     .began (1):   Store initial event, reset tracking state, start monitor
    //     .changed (4): Accumulate deltas, compute smeathed values, compute velocity
    //     .ended (8) / .cancelled (16): Fire onDragEnded, reset, stop monitor
    //     default:      No-op
    //   After switch: If initial event exists, compute velocity from initial to current,
    //     then fire onDragChanged with (cumulative, smeathedDelta, smeathedVelocity)
    func handleScroll(_ event: NSEvent) {
        guard event.momentumPhase == .none else { return }

        switch event.phase {
        case .began:
            //   Store initial event
            self.initialScrollEvent = event

            self.cumulativeTranslation = .zero
            self.smeathedScrollDelta = .zero

            self.lastEventTimestamp = event.timestamp.magnitude

            self.smeathedVelocity = .zero

            startGestureMonitor()

        case .changed:
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY

            self.cumulativeTranslation = CGSize(
                width: cumulativeTranslation.width + deltaX,
                height: cumulativeTranslation.height + deltaY
            )

            let oneMinusAlpha = 1.0 - smeathingFactor
            self.smeathedScrollDelta = CGPoint(
                x: smeathedScrollDelta.x * oneMinusAlpha + deltaX * smeathingFactor,
                y: smeathedScrollDelta.y * smeathingFactor + deltaY * oneMinusAlpha
            )

            let currentTimestamp = event.timestamp.magnitude
            let dt = currentTimestamp - lastEventTimestamp

            lastEventTimestamp = currentTimestamp

            if dt > 0.0 {
                let rawVelocityWidth = deltaX / dt
                let rawVelocityHeight = deltaY / dt
                let oneMinusVelAlpha = 1.0 - velocitySmeathingFactor
                self.smeathedVelocity = CGSize(
                    width: smeathedVelocity.width * oneMinusVelAlpha + rawVelocityWidth * velocitySmeathingFactor,
                    height: smeathedVelocity.height * oneMinusVelAlpha + rawVelocityHeight * velocitySmeathingFactor
                )
            }

        case .ended, .cancelled:
            //   Fire onDragEnded if set
            if let onDragEnded = self.onDragEnded {
                onDragEnded(cumulativeTranslation, smeathedScrollDelta, smeathedVelocity)
            }

            self.cumulativeTranslation = .zero
            self.smeathedScrollDelta = .zero
            self.smeathedVelocity = .zero

            stopGestureMonitor()

            return

        default:
            return
        }

        //   from initial event to current
        guard initialScrollEvent != nil else { return }

        //   If dt > 0: velocity = (currentDelta - initialDelta) / dt
        //   Then fire onDragChanged with (cumulative, smeathedDelta, velocity)
        if let onDragChanged = self.onDragChanged {
            //   The actual velocity is computed in a separate calculateVelocity method
            var callbackVelocity = self.smeathedVelocity

            //   for the onDragChanged callback, using similar dt-based calculation
            //   We pass smeathedVelocity as it already captures the trend

            onDragChanged(cumulativeTranslation, smeathedScrollDelta, callbackVelocity)
        }
    }

    // Computes velocity as: sum of scrollingDeltas from current to initial event,
    //   divided by the time difference between their timestamps
    private func calculateVelocity(currentEvent: NSEvent, initialEvent: NSEvent?) -> CGSize {
        guard let initial = initialEvent else { return .zero }

        let currentTime = currentEvent.timestamp.magnitude
        let initialTime = initial.timestamp.magnitude
        let dt = currentTime - initialTime

        guard dt > 0.0 else { return .zero }

        let deltaX = currentEvent.scrollingDeltaX - initial.scrollingDeltaX
        let deltaY = currentEvent.scrollingDeltaY - initial.scrollingDeltaY

        return CGSize(width: deltaX / dt, height: deltaY / dt)
    }

    // MARK: - Gesture Monitor

    //   Registers a local NSEvent monitor for scroll wheel events (mask .scrollWheel)
    //   Monitor calls handleScroll on incoming events, returns nil only on .began
    func startGestureMonitor() {
        guard scrollMonitor == nil else {
            return
        }

        //   The handler: if phase != .began → handleScroll, return nil (swallow event)
        //   if phase == .began → return event (pass through)
        self.scrollMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .scrollWheel
        ) { [weak self] event in
            guard let self = self else { return event }

            if event.phase != .began {
                self.handleScroll(event)
                return nil
            }

            return event
        }
    }

    //   Removes the local monitor via NSEvent.removeMonitor, nils out token
    func stopGestureMonitor() {
        guard let monitor = scrollMonitor else {
            return
        }

        if let nsMonitor = monitor as? NSObject {
            NSEvent.removeMonitor(nsMonitor)
        }

        scrollMonitor = nil
    }

    // MARK: - Cancel Gesture (internal)

    // Resets cumulativeTranslation, smeathedScrollDelta, nils initialScrollEvent,
    //   stops gesture monitor. Called from onDragChanged callback when gesture is cancelled.
    func cancelGesture() {
        cumulativeTranslation = .zero
        smeathedScrollDelta = .zero

        initialScrollEvent = nil

        stopGestureMonitor()
    }

    // MARK: - Cleanup

    // Deinit: stop monitor if active
    deinit {
        stopGestureMonitor()
    }
}
