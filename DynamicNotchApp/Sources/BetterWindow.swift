import AppKit
import QuartzCore
import ScreenCaptureKit

/// Floating window used for the per-screen notch window and the note windows. Can animate its
/// appearance through a screenshot-backed helper window ("fake screenshot" layer).
class BetterWindow: NSWindow {
    private var fakeScreenshotWindow: NSWindow?

    /// Set for the per-screen notch window (WindowsManager.DisplayKit): a borderless window must
    /// opt in to key status so text fields in widgets (notes, reminders) can take focus.
    var isNotchWindow = false
    override var canBecomeKey: Bool { isNotchWindow ? true : super.canBecomeKey }
    override var canBecomeMain: Bool { isNotchWindow ? false : super.canBecomeMain }
    private var fakeScreenshotLayer: CALayer?

    override init(
        contentRect: CGRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer deferFlag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: deferFlag
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.hasShadow = true
    }

    func convertWindowFrameToScreenFrame(_ rect: CGRect) -> CGRect {
        guard let screen = self.screen else {
            return rect
        }
        let screenFrame = screen.frame
        return rect.offsetBy(dx: screenFrame.origin.x, dy: screenFrame.origin.y)
    }

    func destroyTransformingWindow() {
        fakeScreenshotWindow?.close()
        fakeScreenshotWindow = nil
        fakeScreenshotLayer = nil
    }

    func initializeFakeScreenshotWindow() {
        let screenFrame = screen?.frame ?? .zero
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .clear
        self.fakeScreenshotWindow = window
    }

    func initializeFakeScreenshotWindowLayer() {
        guard let window = fakeScreenshotWindow else { return }
        let layer = CALayer()
        layer.frame = NSRect(origin: .zero, size: window.frame.size)
        layer.contentsGravity = .resizeAspectFill
        window.contentView?.layer = layer
        window.contentView?.wantsLayer = true
        self.fakeScreenshotLayer = layer
    }

    func setupIfNeeded(
        with layerSetup: ((CALayer) -> Void)?,
        closing: Bool,
        cb: @escaping () -> Void
    ) {
        takeScreenshot { [weak self] image in
            guard let self = self else { return }
            defer { cb() }

            if !closing {
                self.initializeFakeScreenshotWindow()
                self.initializeFakeScreenshotWindowLayer()
                if let image = image {
                    self.fakeScreenshotLayer?.contents = image
                }
            }

            if let layer = self.fakeScreenshotLayer {
                layerSetup?(layer)
            }

            if closing {
                self.fakeScreenshotWindow?.close()
                self.destroyTransformingWindow()
            }
        }
    }

    func takeScreenshot(_ completion: ((CGImage?) -> Void)?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // shareable content → display filter → SCScreenshotManager
            let displayID = self.screen?.displayID ?? CGMainDisplayID()
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                guard error == nil, let content = content,
                      let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                    completion?(nil)
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                    completion?(image)
                }
            }
        }
    }

    func animatedClose(
        withDuration duration: Double,
        timing: CAMediaTimingFunction?,
        setup: ((CALayer) -> Void)?,
        animations: @escaping (CALayer) -> Void
    ) {
        setupIfNeeded(with: setup, closing: true) {
            DispatchQueue.main.async {
                self.orderOut(nil)
            }
        }
    }

    func makeKeyAndOrderFront(
        withDuration duration: Double,
        timing: CAMediaTimingFunction?,
        setup: ((CALayer) -> Void)?,
        animations: @escaping (CALayer) -> Void
    ) {
        setupIfNeeded(with: setup, closing: false) {
            DispatchQueue.main.async {
                self.makeKeyAndOrderFront(nil)
            }
        }
    }

    func performAnimations(
        _ animation: @escaping (CALayer) -> Void,
        duration: Double,
        timing: CAMediaTimingFunction?,
        cb: (() -> Void)?
    ) {
        guard let layer = fakeScreenshotLayer else { return }

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        if let timing = timing {
            CATransaction.setAnimationTimingFunction(timing)
        }
        CATransaction.setCompletionBlock(cb)

        animation(layer)

        CATransaction.commit()
    }
}
