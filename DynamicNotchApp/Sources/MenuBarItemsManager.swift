// Menu Bar widget engine (2026-10-20): hides menu bar items behind our own separator status
// item and shows the hidden ones (as live images) inside the open notch.
//
// Public APIs only (technique notes and what was measured on macOS 26: docs/menubar-items-reference.md):
//   - Hiding: `separator`, an NSStatusItem of ours. Items to its LEFT are hidden by giving it a
//     length of `hiddenLength` (10 000 pt): the status area is laid out right-to-left, so everything
//     left of the separator is pushed past the left edge of the screen. Shown again with the
//     normal (chevron) length. The user arranges items with ⌘-drag (system behaviour).
//   - Finding items: `CGWindowListCopyWindowInfo` windows at the status-window level
//     (kCGStatusWindowLevel = 25) on the separator's menu bar row. On macOS 26 every status item
//     window is owned by Control Center, so the owning app is found by (1) the Accessibility API
//     (each app's `AXExtrasMenuBar` children: position/size → app), (2) the window title when it is
//     a bundle identifier, (3) the same item's copy on another display (same offset from that
//     display's right edge and same width), (4) Control Center's own item names (Clock, WiFi …).
//   - Images: ScreenCaptureKit `SCScreenshotManager.captureImage` of each item window
//     (`SCContentFilter(desktopIndependentWindow:)`). Needs Screen Recording; without it the
//     widget shows names and app icons only (window titles are also hidden then).
//   - Clicks: the separator is shrunk for a moment, the item's on-screen frame is read again, and a
//     left/right mouse down/up `CGEvent` is posted at its centre (window-under-pointer fields set
//     to the item's window). Re-hidden once no menu is open. Needs Accessibility (event posting);
//     without it a click just shows the hidden items for a while so the user can click them.
import AppKit
import ApplicationServices
import ScreenCaptureKit
import Observation
import SwiftUI

/// One menu bar item window (CG global coordinates: origin top-left of the primary display).
struct MenuBarItem: Identifiable, Hashable {
    let windowID: CGWindowID
    var frame: CGRect
    /// Window title (status item autosave name or bundle id; empty without Screen Recording).
    var title: String
    var bundleID: String?
    var appName: String
    var id: CGWindowID { windowID }
}

@MainActor
@Observable
final class MenuBarItemsManager {
    static let shared = MenuBarItemsManager()

    /// Separator length that pushes the items to its left off the screen.
    nonisolated static let hiddenLength: CGFloat = 10_000
    /// Status window level (kCGStatusWindowLevel).
    nonisolated static let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
    /// Pop-up menu level (kCGPopUpMenuWindowLevel): an open status item menu.
    nonisolated static let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))

    // MARK: Observed state

    /// Items left of the separator (hidden while it is expanded), left to right.
    private(set) var hiddenItems: [MenuBarItem] = []
    /// Items right of the separator on the same menu bar.
    private(set) var visibleItemCount = 0
    /// Latest captured image per item window.
    private(set) var images: [CGWindowID: CGImage] = [:]
    /// Screen Recording (item images, window titles) — PermissionCenter, observable.
    var screenRecordingGranted: Bool { PermissionCenter.shared.isGranted(.screenRecording) }
    /// Accessibility (owner lookup, click forwarding) — PermissionCenter, observable.
    var accessibilityGranted: Bool { PermissionCenter.shared.isGranted(.accessibility) }
    /// The separator is in the menu bar.
    private(set) var separatorActive = false
    /// The hidden items are currently shown in the menu bar (setting or a forwarded click).
    private(set) var isRevealed = false
    /// Scale of the menu bar's display (captured images are at this scale).
    private(set) var displayScale: CGFloat = 2
    /// Last capture error (logged, shown in the settings).
    private(set) var captureError: String?

    // MARK: Private

    @ObservationIgnored private var separator: NSStatusItem?
    @ObservationIgnored private var transientReveal = false
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var visibleClients = 0
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    @ObservationIgnored private var rehideTimer: Timer?
    @ObservationIgnored private var captureInFlight = false
    @ObservationIgnored private var axScanInFlight = false
    @ObservationIgnored private var axItems: [AXExtrasScanner.Extra] = []
    @ObservationIgnored private var lastAXScan: Date = .distantPast
    /// Unresolved items the last AX scan was run for; a scan that could not resolve them is not
    /// repeated until another item turns up unresolved.
    @ObservationIgnored private var lastAXScanTargets: Set<CGWindowID> = []
    @ObservationIgnored private var lastSignature: [CGWindowID] = []

    private init() {}

    /// Called at launch (AppDelegate): follows the settings (separator only while the widget is in
    /// the Nook and hiding is on).
    func start() {
        guard settingsTask == nil else { return }
        settingsTask = Task { @MainActor [weak self] in
            for await _ in SettingsStore.updates([StoredKeys.nookSettings, StoredKeys.menuBarItemsWidgetSettings]) {
                self?.applySettings()
            }
        }
        #if DEBUG
        MenuBarItemsDebug.install()
        #endif
    }

    // MARK: Separator

    private var settings: MenuBarItemsWidgetSettings { SettingsStore[.menuBarItemsWidgetSettings] }

    func applySettings() {
        let s = settings
        let wanted = s.hidingEnabled && SettingsStore[.nookSettings].widgets.contains(.menuBarItems)
        if wanted { installSeparator() } else { removeSeparator() }
        updateSeparatorLength()
    }

    private static var autosaveName: String {
        var name = "DynamicNotchMenuBarSeparator"
        #if DEBUG
        if let channel = ProcessInfo.processInfo.environment["DN_DEBUG_CHANNEL"], !channel.isEmpty { name += "-" + channel }
        #endif
        return name
    }

    private func installSeparator() {
        guard separator == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.behavior = []   // not removable by dragging it out of the menu bar
        if let button = item.button {
            button.target = self
            button.action = #selector(separatorClicked(_:))
            button.toolTip = String(localized: "Menu bar items to the left of this separator are hidden. Click to show or hide them; ⌘-drag items across it to choose which are hidden.")
            button.setAccessibilityLabel(String(localized: "Hidden menu bar items"))
        }
        separator = item
        separatorActive = true
        NSLog("[MenuBar] separator installed (%@)", Self.autosaveName)
    }

    private func removeSeparator() {
        guard let item = separator else { return }
        NSStatusBar.system.removeStatusItem(item)
        separator = nil
        separatorActive = false
        isRevealed = false
        hiddenItems = []
        visibleItemCount = 0
        NSLog("[MenuBar] separator removed")
    }

    private func updateSeparatorLength() {
        guard let item = separator else { isRevealed = false; return }
        let reveal = settings.showHiddenItems || transientReveal
        isRevealed = reveal
        if reveal {
            item.length = NSStatusItem.variableLength
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let image = NSImage(systemSymbolName: "chevron.compact.left", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            item.button?.image = image
        } else {
            // Blank strip: the visible part (the empty menu bar left of the shown items) stays
            // clickable and shows the hidden items again.
            item.button?.image = nil
            item.length = Self.hiddenLength
        }
    }

    @objc private func separatorClicked(_ sender: Any?) {
        setShowHiddenItems(!settings.showHiddenItems)
    }

    func setShowHiddenItems(_ show: Bool) {
        transientReveal = false
        rehideTimer?.invalidate()
        var s = settings
        s.showHiddenItems = show
        SettingsStore[.menuBarItemsWidgetSettings] = s
        applySettings()
        scheduleRefreshSoon()
    }


    var separatorFrameCG: CGRect? {
        guard let frame = separator?.button?.window?.frame, frame.width > 0 else { return nil }
        return Self.cgRect(fromAppKit: frame)
    }

    nonisolated static func cgRect(fromAppKit r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Screen frame in CG global coordinates.
    nonisolated static func cgFrame(of screen: NSScreen) -> CGRect { cgRect(fromAppKit: screen.frame) }

    // MARK: Visibility (widget on screen → refresh ~1 s)

    func widgetAppeared() {
        visibleClients += 1
        start()
        refreshPermissions()
        refresh()
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { MenuBarItemsManager.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func widgetDisappeared() {
        visibleClients = max(visibleClients - 1, 0)
        if visibleClients == 0 {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func scheduleRefreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MenuBarItemsManager.shared.refresh() }
    }

    // MARK: Permissions (PermissionCenter)

    func refreshPermissions() {
        PermissionCenter.shared.refresh([.screenRecording, .accessibility])
    }

    /// The system prompt the first time, the Privacy pane afterwards (PermissionCenter.request).
    func requestScreenRecording() {
        PermissionCenter.shared.requestAccess(.screenRecording)
    }

    func requestAccessibility() {
        PermissionCenter.shared.requestAccess(.accessibility)
    }

    // MARK: Enumeration

    /// Raw status-level windows (any display), from the window server.
    nonisolated static func statusWindows() -> [(id: CGWindowID, frame: CGRect, title: String, onScreen: Bool)] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == statusLayer,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 0, frame.height > 0 else { return nil }
            return (CGWindowID(number), frame, info[kCGWindowName as String] as? String ?? "",
                    (info[kCGWindowIsOnscreen as String] as? Bool) ?? false)
        }
    }

    /// CG frames of this process's own status item windows (our app icon, the separator).
    private func ownStatusFrames() -> [CGRect] {
        var windows = NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") && $0.frame.width > 0 }
        #if DEBUG
        // The DEBUG test item (DebugHooks-MenuBar.swift) stands in for another app's item.
        if let test = debugTestItem?.button?.window { windows.removeAll { $0 === test } }
        #endif
        return windows.map { Self.cgRect(fromAppKit: $0.frame) }
    }

    /// Re-reads the menu bar (and captures images when allowed). Cheap enough for 1 s while the
    /// widget is shown.
    func refresh() {
        refreshPermissions()
        guard let sep = separatorFrameCG,
              let screen = separator?.button?.window?.screen ?? NSScreen.screens.first else {
            hiddenItems = []
            visibleItemCount = 0
            return
        }
        displayScale = screen.backingScaleFactor
        let screenCG = Self.cgFrame(of: screen)
        let all = Self.statusWindows()
        let row = all.filter { abs($0.frame.minY - sep.minY) < 2 }
        let own = ownStatusFrames()
        func isOwn(_ f: CGRect) -> Bool { own.contains { abs($0.minX - f.minX) < 1.5 && abs($0.width - f.width) < 1.5 } }

        // Separator copies on this row (one per display sharing the row height); an item belongs
        // to our separator when the nearest copy to its right is ours.
        let copies = row.filter { abs($0.frame.width - sep.width) < 1.5 }.map(\.frame)
        let revealed = sep.width < 1000
        let hiddenRaw = row.filter { w in
            guard w.frame.maxX <= sep.minX + 1, !isOwn(w.frame) else { return false }
            if revealed { return w.frame.minX >= screenCG.minX - 1 }
            let nearest = copies.filter { $0.minX >= w.frame.maxX - 1 }.min { $0.minX < $1.minX }
            return nearest.map { abs($0.minX - sep.minX) < 1.5 } ?? false
        }
        .sorted { $0.frame.minX < $1.frame.minX }
        visibleItemCount = row.filter { $0.frame.minX >= sep.maxX - 1 && $0.frame.maxX <= screenCG.maxX + 1 && !isOwn($0.frame) }.count

        let screens = NSScreen.screens.map(Self.cgFrame(of:)).filter { $0 != screenCG }
        hiddenItems = hiddenRaw.map { w in
            let owner = resolveOwner(frame: w.frame, title: w.title, screenCG: screenCG, otherScreens: screens, all: all)
            return MenuBarItem(windowID: w.id, frame: w.frame, title: w.title, bundleID: owner.bundleID, appName: owner.name)
        }
        let signature = hiddenItems.map(\.windowID)
        if signature != lastSignature {
            lastSignature = signature
            images = images.filter { signature.contains($0.key) }
        }
        scanAccessibilityIfNeeded()
        if settings.showItemImages && screenRecordingGranted && !hiddenItems.isEmpty {
            captureImages(hiddenItems)
        }
    }

    // MARK: Owner resolution

    private func resolveOwner(frame: CGRect, title: String, screenCG: CGRect, otherScreens: [CGRect],
                              all: [(id: CGWindowID, frame: CGRect, title: String, onScreen: Bool)]) -> (bundleID: String?, name: String) {
        // 1. Accessibility: the app whose extras-menu-bar child is inside this window.
        if let ax = axItems.first(where: { $0.lies(in: frame) }) {
            if ax.bundleID == "com.apple.controlcenter", let system = Self.systemItemName(title) {
                return (ax.bundleID, system)
            }
            return (ax.bundleID, ax.name)
        }
        // 2. The title is a bundle identifier.
        if let app = Self.app(forBundleID: title) { return app }
        // 3. Its copy on another display (same offset from the right edge, same width).
        let offset = screenCG.maxX - frame.minX
        for screen in otherScreens {
            if let twin = all.first(where: { abs($0.frame.minY - screen.minY) < 2
                && abs((screen.maxX - $0.frame.minX) - offset) < 1.5
                && abs($0.frame.width - frame.width) < 1.5 }),
               let app = Self.app(forBundleID: twin.title) {
                return app
            }
        }
        // 4. Control Center's own items.
        if let system = Self.systemItemName(title) { return ("com.apple.controlcenter", system) }
        return (nil, String(localized: "Menu Bar Item"))
    }

    private static func app(forBundleID id: String) -> (bundleID: String?, name: String)? {
        guard id.contains("."), !id.contains(" ") else { return nil }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            return (id, running.localizedName ?? id)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return (id, FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
        return nil
    }

    /// Names of Control Center's items (window titles, without a "-<n>" suffix).
    static func systemItemName(_ title: String) -> String? {
        let base = title.split(separator: "-").first.map(String.init) ?? title
        let names: [String: String] = [
            "Clock": "Clock", "WiFi": "Wi-Fi", "Sound": "Sound", "Bluetooth": "Bluetooth",
            "Battery": "Battery", "BentoBox": "Control Center", "FocusModes": "Focus",
            "Display": "Display", "NowPlaying": "Now Playing", "Siri": "Siri", "Spotlight": "Spotlight",
            "UserSwitcher": "Fast User Switching", "KeyboardBrightness": "Keyboard Brightness",
            "ScreenMirroring": "Screen Mirroring", "AirDrop": "AirDrop", "Accessibility": "Accessibility Shortcuts",
            "StageManager": "Stage Manager", "Hearing": "Hearing", "AudioVideoModule": "Microphone & Camera",
        ]
        return names[base]
    }

    // MARK: Accessibility scan

    /// Minimum time between two Accessibility scans.
    private static let axScanInterval: TimeInterval = 10

    /// Hidden items without an owner, or whose window no scanned extra lies in.
    private func itemsNeedingAXScan() -> Set<CGWindowID> {
        Set(hiddenItems.filter { item in
            item.bundleID == nil || !axItems.contains { $0.lies(in: item.frame) }
        }.map(\.windowID))
    }

    /// Accessibility scan of every app's extras menu bar (positions → app). Slow apps time out, so
    /// it runs off the main thread, at most every 10 s, and only when an item without an owner turns
    /// up that the previous scan was not already run for (items no app exposes through
    /// AXExtrasMenuBar would otherwise trigger a full scan every 10 s forever).
    private func scanAccessibilityIfNeeded() {
        guard accessibilityGranted, !axScanInFlight else { return }
        let targets = itemsNeedingAXScan()
        guard !targets.isEmpty, !targets.isSubset(of: lastAXScanTargets),
              Date().timeIntervalSince(lastAXScan) > Self.axScanInterval else { return }
        axScanInFlight = true
        lastAXScan = Date()
        lastAXScanTargets = targets
        let apps = NSWorkspace.shared.runningApplications.map {
            AXExtrasScanner.App(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier,
                                name: $0.localizedName ?? $0.bundleIdentifier ?? "")
        }
        DispatchQueue.global(qos: .utility).async {
            let found = AXExtrasScanner.scan(apps)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let m = MenuBarItemsManager.shared
                    m.axItems = found
                    m.axScanInFlight = false
                    m.refresh()
                }
            }
        }
    }

    // MARK: Images (ScreenCaptureKit)

    private func captureImages(_ items: [MenuBarItem]) {
        guard !captureInFlight else { return }
        captureInFlight = true
        let scale = displayScale
        Task { @MainActor in
            defer { self.captureInFlight = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                var byID: [CGWindowID: SCWindow] = [:]
                for w in content.windows { byID[w.windowID] = w }
                var captured: [CGWindowID: CGImage] = [:]
                for item in items {
                    guard let window = byID[item.windowID] else { continue }
                    let config = SCStreamConfiguration()
                    config.width = max(Int(item.frame.width * scale), 1)
                    config.height = max(Int(item.frame.height * scale), 1)
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    config.captureResolution = .best
                    if let image = try? await SCScreenshotManager.captureImage(
                        contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config),
                       !Self.isBlank(image) {
                        captured[item.windowID] = image
                    }
                }
                for (id, image) in captured { self.images[id] = image }
                self.captureError = nil
            } catch {
                self.captureError = error.localizedDescription
                NSLog("[MenuBar] capture failed: %@", "\(error)")
            }
        }
    }

    /// True when every pixel is fully transparent (an item that is not drawn while off-screen).
    nonisolated static func isBlank(_ image: CGImage) -> Bool {
        let w = 16, h = 16
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return !stride(from: 3, to: data.count, by: 4).contains { data[$0] > 8 }
    }

    /// Mean luminance of the opaque pixels (0…1): dark item images get a light tile in the widget.
    nonisolated static func luminance(_ image: CGImage) -> CGFloat {
        let w = 24, h = 12
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum: CGFloat = 0, weight: CGFloat = 0
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 40 {
            let a = CGFloat(data[i + 3])
            // premultiplied: divide back by alpha
            let r = CGFloat(data[i]) / a, g = CGFloat(data[i + 1]) / a, b = CGFloat(data[i + 2]) / a
            sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) * a
            weight += a
        }
        return weight > 0 ? sum / weight : 1
    }

    // MARK: Click forwarding

    /// Forwards a click to the real item: shows the hidden items, posts the click at the item's
    /// centre, and hides them again once its menu has closed.
    func activate(_ item: MenuBarItem, rightClick: Bool) {
        refreshPermissions()
        closeNotch()
        let wasRevealed = isRevealed
        if !wasRevealed {
            transientReveal = true
            updateSeparatorLength()
        }
        guard accessibilityGranted else {
            // No event posting: leave the items shown for a while so the user can click them.
            if !wasRevealed { scheduleRehide(minimum: 8, requireNoMenu: true) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasRevealed ? 0.05 : 0.45)) {
            MainActor.assumeIsolated {
                let m = MenuBarItemsManager.shared
                guard let frame = Self.statusWindows().first(where: { $0.id == item.windowID })?.frame,
                      NSScreen.screens.map(Self.cgFrame(of:)).contains(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else {
                    NSLog("[MenuBar] item %u is not on screen; not clicking", item.windowID)
                    if !wasRevealed { m.scheduleRehide(minimum: 4, requireNoMenu: true) }
                    return
                }
                Self.postClick(at: CGPoint(x: frame.midX, y: frame.midY), windowID: item.windowID, rightClick: rightClick)
                NSLog("[MenuBar] forwarded %@ click to %@ (%u) at %@", rightClick ? "right" : "left", item.appName, item.windowID, NSStringFromRect(frame))
                if !wasRevealed { m.scheduleRehide(minimum: 1.5, requireNoMenu: true) }
            }
        }
    }

    nonisolated static func postClick(at point: CGPoint, windowID: CGWindowID, rightClick: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let original = CGEvent(source: nil)?.location
        let types: (CGEventType, CGEventType) = rightClick ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        let button: CGMouseButton = rightClick ? .right : .left
        for type in [types.0, types.1] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { continue }
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            event.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        if let original { CGWarpMouseCursorPosition(original) }
    }

    /// Moves a hidden item to the shown part (⌘-drag to just right of the separator). Only on an
    /// explicit request (Settings / widget), Accessibility needed.
    func moveToShown(_ item: MenuBarItem) {
        refreshPermissions()
        guard accessibilityGranted else { requestAccessibility(); return }
        let wasRevealed = isRevealed
        if !wasRevealed { transientReveal = true; updateSeparatorLength() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            MainActor.assumeIsolated {
                let m = MenuBarItemsManager.shared
                defer { if !wasRevealed { m.scheduleRehide(minimum: 0.8, requireNoMenu: false) } }
                guard let frame = Self.statusWindows().first(where: { $0.id == item.windowID })?.frame,
                      let sep = m.separatorFrameCG else { return }
                let start = CGPoint(x: frame.midX, y: frame.midY)
                let end = CGPoint(x: sep.maxX + 4, y: frame.midY)
                Self.postCommandDrag(from: start, to: end)
                NSLog("[MenuBar] moved %@ (%u) right of the separator", item.appName, item.windowID)
            }
        }
    }

    nonisolated static func postCommandDrag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let original = CGEvent(source: nil)?.location
        func post(_ type: CGEventType, _ p: CGPoint) {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
            e.flags = .maskCommand
            e.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start); usleep(30_000)
        post(.leftMouseDown, start); usleep(60_000)
        for i in 1...12 {
            let t = CGFloat(i) / 12
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y)); usleep(15_000)
        }
        post(.leftMouseUp, end); usleep(30_000)
        if let original { CGWarpMouseCursorPosition(original) }
    }

    /// Hides the items again after a forwarded click: after `minimum` seconds, once no pop-up menu
    /// is open (checked twice in a row) and the pointer has left the menu bar; at the latest after
    /// 60 s.
    private func scheduleRehide(minimum: TimeInterval, requireNoMenu: Bool) {
        rehideTimer?.invalidate()
        let started = Date()
        var quietChecks = 0
        let timer = Timer(timeInterval: 0.5, repeats: true) { timer in
            MainActor.assumeIsolated {
                let m = MenuBarItemsManager.shared
                let elapsed = Date().timeIntervalSince(started)
                guard elapsed >= minimum else { return }
                let menuOpen = requireNoMenu && Self.isMenuOpen()
                let pointerInBar = m.pointerInMenuBar()
                quietChecks = (menuOpen || pointerInBar) ? 0 : quietChecks + 1
                if quietChecks >= 2 || elapsed > 60 {
                    timer.invalidate()
                    m.rehideTimer = nil
                    m.transientReveal = false
                    m.updateSeparatorLength()
                    m.scheduleRefreshSoon()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rehideTimer = timer
    }

    nonisolated static func isMenuOpen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { ($0[kCGWindowLayer as String] as? Int) == menuLayer }
    }

    private func pointerInMenuBar() -> Bool {
        guard let sep = separatorFrameCG, let p = CGEvent(source: nil)?.location else { return false }
        return p.y >= sep.minY - 1 && p.y <= sep.maxY + 1
    }

    private func closeNotch() {
        withAnimation { for state in DynamicNotchState.perScreen.values { state.mode = .closed } }
    }

    // MARK: DEBUG

    #if DEBUG
    @ObservationIgnored var debugTestItem: NSStatusItem?
    #endif
}

// MARK: - Accessibility: apps' extras menu bars

/// Reads every app's `AXExtrasMenuBar` children (their screen frames), off the main thread.
private enum AXExtrasScanner {
    struct App: Sendable {
        let pid: pid_t
        let bundleID: String?
        let name: String
    }

    /// One status item an app exposes (frame in CG global coordinates, like the item windows).
    struct Extra: Sendable {
        let pid: pid_t
        let bundleID: String?
        let name: String
        let frame: CGRect

        /// The extra's centre lies in `windowFrame` (with a small tolerance).
        func lies(in windowFrame: CGRect) -> Bool {
            frame.width > 0 && windowFrame.insetBy(dx: -1, dy: -2).contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    /// Per-app messaging timeout: a hung app must not stall the scan.
    static let timeout: Float = 0.1

    static func scan(_ apps: [App]) -> [Extra] {
        apps.flatMap { app -> [Extra] in
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, timeout)
            guard let bar = element.element("AXExtrasMenuBar") else { return [] }
            return bar.children.compactMap { child in
                let origin = child.point(kAXPositionAttribute) ?? .zero
                let size = child.size(kAXSizeAttribute) ?? .zero
                guard size.width > 0 else { return nil }
                return Extra(pid: app.pid, bundleID: app.bundleID, name: app.name, frame: CGRect(origin: origin, size: size))
            }
        }
    }
}

private extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success ? value : nil
    }

    /// An attribute holding another element.
    func element(_ name: String) -> AXUIElement? {
        guard let value = attribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    var children: [AXUIElement] {
        (attribute(kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    /// A CGPoint AXValue attribute (nil when missing or of another type).
    func point(_ name: String) -> CGPoint? {
        var p = CGPoint.zero
        guard let value = axValue(name), AXValueGetValue(value, .cgPoint, &p) else { return nil }
        return p
    }

    /// A CGSize AXValue attribute (nil when missing or of another type).
    func size(_ name: String) -> CGSize? {
        var s = CGSize.zero
        guard let value = axValue(name), AXValueGetValue(value, .cgSize, &s) else { return nil }
        return s
    }

    private func axValue(_ name: String) -> AXValue? {
        guard let value = attribute(name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
