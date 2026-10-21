import AppKit
import SwiftUI

/// Owns one `DisplayKit` per screen (notch window, notch state, window geometry) and keeps the set
/// in sync with the connected screens; also opens note windows and the settings window.
class WindowsManager {

    // MARK: - Stored properties

    var debouncedWorkItem: DispatchWorkItem?

    /// Screen configurations at the last update, keyed by display ID (the `\.displayKitId`
    /// environment value).
    var lastKnownScreenConfigurations: [CGDirectDisplayID: NSScreen.Configuration] = [:]

    var displayKits: [CGDirectDisplayID: DisplayKit] = [:]

    // MARK: - Singleton

    static let shared: WindowsManager = {
        let mgr = WindowsManager()
        mgr.setupObservers()
        return mgr
    }()

    private init() {}

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debouncedUpdateWindows()
        }
    }

    /// Coalesces screen-parameter changes: updates the windows 1 s after the last one.
    func debouncedUpdateWindows() {
        if let existing = debouncedWorkItem {
            existing.cancel()
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateWindows()
        }

        debouncedWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.0,
            execute: workItem
        )
    }

    /// A screen was added or removed, or a frame / visible frame changed.
    func hasSignificantScreenChanges() -> Bool {
        let currentScreens = NSScreen.screens

        if currentScreens.count != lastKnownScreenConfigurations.count {
            return true
        }

        for screen in currentScreens {
            let key = screen.displayID
            let current = screen.configuration
            guard let last = lastKnownScreenConfigurations[key],
                  last.frame == current.frame,
                  last.visibleFrame == current.visibleFrame else {
                return true
            }
        }
        return false
    }

    func setupDisplayKitForScreen(_ screen: NSScreen) -> DisplayKit {
        let displayKit = DisplayKit(screen: screen)
        displayKits[screen.displayID] = displayKit
        displayKit.setupDynamicNotchWindow()
        return displayKit
    }

    func showIndicator(_ indicator: Indicator?, _ show: Bool) {
        guard let displayKit = displayKits.first?.value else { return }
        if show, let indicator = indicator {
            displayKit.showIndicator(indicator)
        } else {
            displayKit.hideIndicator()
        }
    }

    func updateLastKnownScreenConfigurations() {
        var configs: [CGDirectDisplayID: NSScreen.Configuration] = [:]
        for screen in NSScreen.screens {
            configs[screen.displayID] = screen.configuration
        }
        lastKnownScreenConfigurations = configs
    }

    /// Syncs the display kits with the connected screens: tears down kits of removed screens and
    /// creates or re-frames the notch window of every other screen.
    func updateWindows() {
        guard hasSignificantScreenChanges() else { return }

        updateLastKnownScreenConfigurations()

        let current = Set(NSScreen.screens.map(\.displayID))
        var removedAny = false
        for (id, kit) in displayKits where !current.contains(id) {
            kit.cleanup()
            displayKits[id] = nil
            removedAny = true
        }
        #if canImport(FanControlKit)
        // a Nook that was open only on the removed screen must not leave fan polling
        // paused / un-paused: re-evaluate from the remaining screens
        if removedAny {
            MainActor.assumeIsolated {
                FanControlNookVisibility.nookVisibilityChanged(isVisible: DynamicNotchState.anyScreen(in: .nook))
            }
        }
        #endif
        for screen in NSScreen.screens {
            if let kit = displayKits[screen.displayID] {
                kit.screen = screen
                kit.setupDynamicNotchWindow()
            } else {
                _ = setupDisplayKitForScreen(screen)
            }
        }
    }

    func openNoteWindow(_ note: Note, inDisplayKitId displayId: CGDirectDisplayID, isCodeMode: Bool) {
        guard let displayKit = displayKits[displayId] else { return }
        let window = BetterWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.makeKeyAndOrderFront(withDuration: 0.3, timing: nil, setup: nil) { _ in }
        displayKit.addWindow(window)
    }

    func showSettings(pane: AppSettings.PaneIdentifier? = nil) {
        // native SwiftUI `Settings` scene (SettingsRootView.swift): select the tab, then open /
        // focus the window (SettingsWindowOpener.swift)
        MainActor.assumeIsolated {
            if let pane { SettingsNavigation.shared.pane = pane }
            SettingsWindowOpener.open()
        }
    }

    // MARK: - WindowsManager.DisplayKit

    /// One screen's notch: its window, per-screen notch state and window geometry.
    final class DisplayKit {
        var screen: NSScreen
        var dynamicnotchWindow: BetterWindow?
        var noteWindows: [BetterWindow] = []
        var indicatorWindow: BetterWindow?
        var settingsPane: AppSettings.PaneIdentifier?
        /// Per-screen notch state (closed / nook / tray…) and window geometry, so only the notch
        /// under the pointer opens (DynamicNotchState.perScreen).
        let notchState = DynamicNotchState()
        let notchGeometry = NotchWindowGeometry()
        private let displayID: CGDirectDisplayID
        /// Hardware notch size the hosted RootView was built with (rebuilt when a scaling or
        /// resolution change alters it).
        var builtNotchSize: CGSize = .zero

        init(screen: NSScreen) {
            self.screen = screen
            self.displayID = screen.displayID
            DynamicNotchState.perScreen[displayID] = notchState
        }

        func addWindow(_ window: BetterWindow) {
            noteWindows.append(window)
        }


        func showIndicator(_ indicator: Indicator) {}
        func hideIndicator() {}

        func cleanup() {
            for window in noteWindows {
                window.close()
            }
            noteWindows.removeAll()
            dynamicnotchWindow?.orderOut(nil)
            dynamicnotchWindow?.close()
            dynamicnotchWindow = nil
            if DynamicNotchState.perScreen[displayID] === notchState {
                DynamicNotchState.perScreen[displayID] = nil
            }
        }
    }
}

// MARK: - Notch window

// One BetterWindow per screen: borderless, transparent, above the menu bar, on all Spaces, pinned
// to the top centre of the screen, hosting RootView in an AcceptingFirstClickHostingView. Its size
// follows the open notch (NotchWindowGeometry: open width + overshoot margin, clamped to the
// screen); it is refitted only when the open width changes (widget set / sizes), never per
// animation frame — the open/close animation is done entirely in SwiftUI (NotchView).
extension WindowsManager.DisplayKit {
    /// Creates (or re-frames) this screen's notch window. Called on the main thread.
    func setupDynamicNotchWindow() {
        MainActor.assumeIsolated { setupDynamicNotchWindowOnMain() }
    }

    /// Open width for the current widget set on this screen.
    private func currentOpenWidth() -> CGFloat {
        let settings = SettingsStore[.nookSettings]
        return NookWidgetLayout.windowOpenWidth(settings, maxWidth: notchGeometry.maxOpenWidth) // F9: widest page
    }

    @MainActor private func setupDynamicNotchWindowOnMain() {
        NotchInteractionMonitor.install()
        notchGeometry.update(screen: screen)
        #if DEBUG
        if DebugHooks.offscreenPanels { notchGeometry.horizontalOffset = -20_000 } // development instance
        #endif
        let frame = notchGeometry.frame(forOpenWidth: currentOpenWidth())
        if let existing = dynamicnotchWindow {
            notchGeometry.fit(openWidth: currentOpenWidth())
            // RootView captures the hardware notch size at creation and injects it as \.notchSize;
            // a scaling ("More Space" / "Larger Text") or resolution change alters it in points
            // without changing the display ID. Rebuild the hosted root view when it changed.
            let notchSize = screen.hardwareNotchSize
            if notchSize != builtNotchSize {
                builtNotchSize = notchSize
                let root = RootView(screenNotchSize: notchSize, notchState: notchState,
                                    geometry: notchGeometry, window: existing)
                let hosting = AcceptingFirstClickHostingView(rootView: root)
                hosting.frame = existing.contentView?.frame ?? NSRect(origin: .zero, size: existing.frame.size)
                hosting.autoresizingMask = [.width, .height]
                hosting.sizingOptions = []
                existing.contentView = hosting
            }
            return
        }
        let window = BetterWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // BetterWindow.init sets level .floating / canJoinAllSpaces+stationary / shadow; the notch
        // window overrides what a notch needs.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isNotchWindow = true
        notchGeometry.window = window
        notchGeometry.canvas = frame.size
        builtNotchSize = screen.hardwareNotchSize
        let root = RootView(screenNotchSize: builtNotchSize, notchState: notchState,
                            geometry: notchGeometry, window: window)
        let hosting = AcceptingFirstClickHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        // Never let SwiftUI resize the window from the content's ideal size.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setFrame(frame, display: false)
        #if DEBUG
        if DebugHooks.ghostPanels { window.alphaValue = 0.02; window.ignoresMouseEvents = true }
        #endif
        window.orderFrontRegardless()
        dynamicnotchWindow = window
    }
}
