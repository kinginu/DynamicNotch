import AppKit

extension NSScreen {
    /// Hardware notch size in points; screens without a notch get a menu-bar-height pseudo notch.
    var hardwareNotchSize: CGSize {
        let top = safeAreaInsets.top
        if top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            return CGSize(width: frame.width - left.width - right.width, height: top)
        }
        let menuBar = frame.maxY - visibleFrame.maxY
        return CGSize(width: 200, height: max(menuBar, 24))
    }
}
