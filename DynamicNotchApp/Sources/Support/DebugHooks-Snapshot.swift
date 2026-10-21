// DEBUG-only offscreen renderer shared by every `<widget>preview:<dir>` command (2026-10-20,
// R15). Replaces the dozen copies of "NSHostingView in a borderless window at −10 000 pt →
// cacheDisplay → PNG" that each widget's debug file carried.
//
// Uniform argument of the snapshot commands:
//   <dir>[?appearance=dark|light|both][&glass=off|on|both][&settle=<seconds>]
//     appearance  which colour schemes to render (default: what the command always rendered —
//                 usually both; dark-only previews such as fanpreview / weatherpreview stay dark)
//     glass       off  = the NookGlass material fallback (default for widget previews: Liquid Glass
//                        layers are not captured by cacheDisplay, they would render flat/empty)
//                 on   = live Liquid Glass (files get a "-glass" suffix)
//                 both = render the whole set twice
//     settle      seconds the run loop runs before capturing (default per command, ~0.5 s)
// File names stay those of the commands (`<name>-<dark|light>.png`), so earlier scripts keep working.
//
// Fixed sizes: a Nook widget cell is `cellHeight` (202 pt) tall at its grid width, rendered inside
// a 12 pt inset (`inset`) on black (dark) or the window background (light); settings panes are
// rendered at 520 pt wide (`settingsWidth`) unless the command says otherwise.
#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum WidgetSnapshotter {
    /// Height of a widget cell in the open Nook (= WidgetGalleryDebug.rowHeight).
    nonisolated static let cellHeight: CGFloat = 202
    /// Margin around a cell in the PNG.
    nonisolated static let inset: CGFloat = 12
    /// Default width of a widget's settings pane render.
    nonisolated static let settingsWidth: CGFloat = 520

    enum GlassMode: Equatable {
        /// `NookGlass.forceFallback = true` (materials; what cacheDisplay can capture)
        case fallback
        /// `NookGlass.forceFallback = false` (Liquid Glass; files get "-glass")
        case native
        /// leave `NookGlass.forceFallback` as it is (DN_DEBUG_NOGLASS decides)
        case inherit
    }

    struct Options {
        /// nil = the command's default
        var appearances: [Bool]?
        var glass: [GlassMode]?
        var settle: TimeInterval?

        /// Splits "<dir>?k=v&k=v" into the directory and the options.
        static func parse(_ arg: String) -> (dir: URL, options: Options) {
            var options = Options()
            guard let q = arg.firstIndex(of: "?") else { return (URL(fileURLWithPath: (arg as NSString).expandingTildeInPath), options) }
            let path = String(arg[..<q])
            for pair in arg[arg.index(after: q)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).lowercased() }
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "appearance", "appearances", "scheme":
                    options.appearances = kv[1] == "dark" ? [true] : kv[1] == "light" ? [false] : [true, false]
                case "glass":
                    options.glass = kv[1] == "on" ? [.native] : kv[1] == "both" ? [.fallback, .native] : [.fallback]
                case "settle":
                    options.settle = TimeInterval(kv[1])
                default:
                    NSLog("[Snapshot] unknown option %@", kv[0])
                }
            }
            return (URL(fileURLWithPath: (path as NSString).expandingTildeInPath), options)
        }
    }

    private static var options = Options()
    private static var fileSuffix = ""
    private static var tag = "[Snapshot]"

    // MARK: Session

    /// Parses the command argument, creates the directory and runs `body` once per glass mode
    /// (`glass` = the command's default when the argument names none), with `NookGlass.forceFallback`
    /// set accordingly and restored afterwards. `tag` prefixes the "wrote …" log lines.
    static func session(_ arg: String, tag: String, glass: GlassMode = .fallback, _ body: (URL) -> Void) {
        let (dir, parsed) = Options.parse(arg)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saved = (options, fileSuffix, self.tag, NookGlass.forceFallback)
        defer { (options, fileSuffix, self.tag, NookGlass.forceFallback) = saved }
        options = parsed
        self.tag = tag
        let modes = parsed.glass ?? [glass]
        for mode in modes {
            switch mode {
            case .fallback: NookGlass.forceFallback = true
            case .native: NookGlass.forceFallback = false
            case .inherit: NookGlass.forceFallback = saved.3
            }
            fileSuffix = (mode == .native && parsed.glass != nil) ? "-glass" : ""
            body(dir)
        }
    }

    /// The colour schemes to render (true = dark): the argument's `appearance=`, else `defaults`.
    static func appearances(default defaults: [Bool] = [true, false]) -> [Bool] {
        options.appearances ?? defaults
    }

    static func scheme(_ dark: Bool) -> String { dark ? "dark" : "light" }

    // MARK: Composition

    /// A widget cell: `width` × `height`, clipped, inset by 12 pt, on black (dark) or the window
    /// background (light), in that colour scheme.
    static func cell<V: View>(_ view: V, width: CGFloat, height: CGFloat = cellHeight,
                              dark: Bool, alignment: Alignment = .center) -> some View {
        view
            .frame(width: width, height: height, alignment: alignment)
            .clipped()
            .padding(inset)
            .background(dark ? Color.black : Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// Renders `make()` as a widget cell for every requested appearance →
    /// `dir/<name>-<dark|light>.png`.
    static func widget<V: View>(_ name: String, in dir: URL, width: CGFloat, height: CGFloat = cellHeight,
                                alignment: Alignment = .center, appearances defaults: [Bool] = [true, false],
                                settle: TimeInterval = 0.5, _ make: () -> V) {
        for dark in appearances(default: defaults) {
            write(cell(make(), width: width, height: height, dark: dark, alignment: alignment),
                  size: CGSize(width: width + 2 * inset, height: height + 2 * inset), dark: dark,
                  to: dir.appendingPathComponent("\(name)-\(scheme(dark)).png"), settle: settle)
        }
    }

    /// Renders a settings view at a fixed size (on the window background unless `background` is
    /// false) for every requested appearance → `dir/<name>-<dark|light>.png`.
    static func settings<V: View>(_ name: String, in dir: URL, size: CGSize, background: Bool = true,
                                  settle: TimeInterval = 0.5, _ make: () -> V) {
        for dark in appearances() {
            let view = make()
                .frame(width: size.width, height: size.height)
                .background(background ? Color(nsColor: .windowBackgroundColor) : Color.clear)
                .environment(\.colorScheme, dark ? .dark : .light)
            write(view, size: size, dark: dark, to: dir.appendingPathComponent("\(name)-\(scheme(dark)).png"), settle: settle)
        }
    }

    // MARK: Rendering

    /// Renders `view` at `size` in a borderless offscreen window and writes a PNG to `url` (with the
    /// session's "-glass" suffix when rendering Liquid Glass). `dark` sets the window appearance
    /// (nil = inherit the app's). `settle` = seconds of run loop before capturing (onAppear, @Query,
    /// async thumbnails); the argument's `settle=` overrides it.
    static func write<V: View>(_ view: V, size: CGSize, dark: Bool?, to url: URL, settle: TimeInterval = 0.5) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let dark { window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
        window.contentView = host
        window.orderFrontRegardless()
        let wait = options.settle ?? settle
        if wait > 0 { RunLoop.current.run(until: Date().addingTimeInterval(wait)) }
        host.layoutSubtreeIfNeeded()
        host.display()
        var target = url
        if !fileSuffix.isEmpty {
            let base = url.deletingPathExtension().lastPathComponent
            target = url.deletingLastPathComponent().appendingPathComponent(base + fileSuffix).appendingPathExtension(url.pathExtension)
        }
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: target)
                NSLog("%@ wrote %@", tag, target.path)
            }
        }
        window.orderOut(nil)
        window.close()
    }
}
#endif
