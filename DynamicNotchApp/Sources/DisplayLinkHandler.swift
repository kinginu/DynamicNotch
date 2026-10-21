import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Timer-driven frame callback used by
//   VibratingCircleNSView and AudioSpectrographNSView (start/stop/isRunning/elapsedTime/callback).
class DisplayLinkHandler {
    var callback: (() -> Void)?
    private(set) var isRunning: Bool = false
    private var timer: Timer?
    private var startTime: CFTimeInterval?
    private let fps: Double

    /// Seconds since start(), or nil when never started.
    var elapsedTime: Double? {
        guard let startTime else { return nil }
        return CACurrentMediaTime() - startTime
    }

    init(fps: Double = 60) {
        self.fps = fps
    }

    convenience init(target: AnyObject? = nil, fps: Double, _ callback: @escaping () -> Void) {
        self.init(fps: fps)
        self.callback = callback
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if startTime == nil { startTime = CACurrentMediaTime() }
        let t = Timer(timeInterval: 1.0 / max(fps, 1), repeats: true) { [weak self] _ in
            self?.callback?()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    deinit { timer?.invalidate() }
}
