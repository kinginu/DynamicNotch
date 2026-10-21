// DEBUG: offscreen PNG writer shared by the widget galleries (refactor R13, 2026-10-20).
// Hosts the view in a borderless window far off screen with the given appearance, lets it settle,
// and writes `cacheDisplay` output to `url` (materials / Liquid Glass render flat in these
// snapshots, hence `NookGlass.forceFallback` in the galleries).
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum NookWidgetSnapshot {
    /// Renders `view` at `size` (dark or light appearance) and writes a PNG; logs "<tag> wrote <path>".
    static func writePNG<V: View>(_ view: V, dark: Bool, size: CGSize, to url: URL,
                                  tag: String, settle: TimeInterval = 0.5) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        host.layoutSubtreeIfNeeded()
        host.display()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                NSLog("%@ wrote %@", tag, url.path)
            }
        }
        window.orderOut(nil)
        window.contentView = nil
    }
}
#endif
