import AppKit
import Observation

/// Tracks which screens show a fullscreen window of another app (the notch closes and hides while
/// one is frontmost). Needs Accessibility trust; without it every screen reports false.
@Observable
class FullscreenMonitor: NSObject {
    static let shared = FullscreenMonitor()

    /// Some screen currently shows a fullscreen window.
    var isFullScreen: Bool { fullScreenStateDict.values.contains(true) }

    var fullScreenStateDict: [NSScreen: Bool] = [:]

    private let workspaceNotificationCenter: NotificationCenter

    override init() {
        workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        super.init()
        setupObservers()
        if AXIsProcessTrustedWithOptions(nil) {
            fullScreenStateDict = getFullscreenStates()
        } else {
            fullScreenStateDict = [:]
        }
    }

    /// Re-evaluates on Space changes, screen parameter changes, windows moving between screens and
    /// screen lock / unlock.
    private func setupObservers() {
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(somethingChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(somethingChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(somethingChanged),
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(somethingChanged),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(somethingChanged),
            name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func somethingChanged() {
        DispatchQueue.main.async(qos: .unspecified) { [weak self] in
            guard let self = self else { return }
            let newStates = self.getFullscreenStates()
            self.fullScreenStateDict = newStates
        }
    }

    /// A screen is fullscreen when a normal-layer window of another app exactly fills its frame.
    private func getFullscreenStates() -> [NSScreen: Bool] {
        guard AXIsProcessTrustedWithOptions(nil) else {
            return [:]
        }

        var result: [NSScreen: Bool] = [:]

        // Without `.excludeDesktopElements` and the layer filter, the Dock's wallpaper window
        // (exactly the display bounds) would match every screen. CG window bounds (top-left
        // origin, y down) are converted to Cocoa coordinates before comparing with NSScreen frames.
        let windowList = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]]) ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // CG global space has its origin at the top-left of the primary display (screens[0])
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let candidateFrames: [CGRect] = windowList.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return CGRect(x: cgBounds.origin.x, y: primaryHeight - cgBounds.maxY,
                          width: cgBounds.width, height: cgBounds.height)
        }

        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            result[screen] = candidateFrames.contains { windowFrame in
                abs(windowFrame.origin.x - screenFrame.origin.x) < 1.0 &&
                    abs(windowFrame.origin.y - screenFrame.origin.y) < 1.0 &&
                    abs(windowFrame.size.width - screenFrame.size.width) < 1.0 &&
                    abs(windowFrame.size.height - screenFrame.size.height) < 1.0
            }
        }

        return result
    }

    private func updateAccessibilityStatus() {
        if AXIsProcessTrustedWithOptions(nil) {
            fullScreenStateDict = getFullscreenStates()
        } else {
            fullScreenStateDict = [:]
        }
    }
}
