// Media / HUD view helpers: the `bouncySmooth` animation preset, NSColor brightness helpers
// (lighter / darker / shaded variants), and the media settings keys.
import AppKit
import SwiftUI

extension Animation {
    /// App-level animation preset used by the media views and NotchView.
    static var bouncySmooth: Animation { .smooth(duration: 0.4, extraBounce: 0.15) }
}

extension NSColor {
    private func adjustedBrightness(_ delta: CGFloat) -> NSColor {
        guard let c = usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s, brightness: min(max(b + delta, 0), 1), alpha: a)
    }

    /// Brightness raised by `amount` (0…1).
    func lighter(amount: CGFloat = 0.2) -> NSColor { adjustedBrightness(amount) }
    /// Brightness lowered by `amount` (0…1).
    func darkened(amount: CGFloat = 0.2) -> NSColor { adjustedBrightness(-amount) }
    /// Mixed with black by `amount` (0…1).
    func shaded(amount: CGFloat = 0.2) -> NSColor { blended(withFraction: min(max(amount, 0), 1), of: .black) ?? self }
}

extension StoredKeys {
    static let mediaLiveActivitySettings = Key<MediaLiveActivitySettings>(SettingKey.mediaLiveActivitySettings, default: .init())
    static let mediaWidgetSettings = Key<MediaWidgetSettings>(SettingKey.mediaWidgetSettings, default: .init())
}
