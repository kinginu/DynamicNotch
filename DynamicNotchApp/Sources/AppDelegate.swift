import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// NSApplicationDelegate implementation for DynamicNotch app lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {

    // Status bar item for menu bar presence
    private var statusItem: NSStatusItem?

    // MARK: - init()

    // Standard init, registers as application delegate
    override init() {
        super.init()
        // Register self as delegate on NSApp.shared
        // dropped: the app entry point installs this via @NSApplicationDelegateAdaptor
        // NSApplication.shared.delegate = self
    }

    // MARK: - applicationDidFinishLaunching

    // applicationDidFinishLaunching(_:)
    // Sets up menu bar item, initializes window and services
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar item
        setupMenu()

        // Start observation of defaults/preferences

        // notch windows (one per screen) and the settings window (WindowsManager.swift)
        WindowsManager.shared.updateWindows()
        WindowsManager.shared.setupSettingsWindow()
        #if canImport(FanControlKit)
        // fan-control-integration.md (e) (Support/FanControl-Patches.swift)
        MainActor.assumeIsolated { FanControlStartup.applicationDidFinishLaunching() }
        #endif
        // live-activity monitors (LiveActivities/LiveActivityCenter.swift)
        MainActor.assumeIsolated { LiveActivitiesStartup.start() }
        // resume saved running timers at launch (not only when the notch opens)
        _ = NookTimersStore.shared
        // mirror the real login-item state into GeneralSettings.launchAtLogin
        //   (Support/LoginItemManager.swift)
        LoginItemManager.syncSetting()
        // Clipboard history records from launch (not only once the widget was shown).
        MainActor.assumeIsolated { ClipboardHistoryManager.shared.start() }
        // Menu Bar widget: its separator status item follows the settings from launch.
        MainActor.assumeIsolated { MenuBarItemsManager.shared.start() }
        // F8: Downloads widget — watches its folder while the widget is in the Nook (closed-notch progress)
        MainActor.assumeIsolated { DownloadsWatcher.shared.activate() }
        // Usage widget: records app usage from launch while turned on (off by default).
        MainActor.assumeIsolated { UsageStartup.applicationDidFinishLaunching() }
        // remove AirDrop/drop temp files left by a previous session
        //   (Support/NotchDrop.swift)
        NotchDropTempFiles.cleanUpStale()
        #if DEBUG
        DebugHooks.install() // verification hooks (Support/DebugHooks.swift)
        #endif
    }

    // F4: `dynamicnotch://` command URLs (CFBundleURLTypes in project.yml; Sources/Automation/,
    // docs/automation.md)
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { URLCommandRouter.shared.handle(urls) } // F4:
    }

    // MARK: - setupMenu

    // setupMenu()
    // Creates NSStatusItem with custom NSMenu for menu bar interaction
    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        guard let button = statusItem?.button else { return }

        // menu bar extras use a monochrome template image (HIG); the text title
        //   "DynamicNotch" is only a fallback.
        if let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                               accessibilityDescription: "DynamicNotch") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "DynamicNotch"
        }
        button.toolTip = "DynamicNotch"

        // standard, localized items: "Settings…" (⌘,) and "Quit DynamicNotch" (⌘Q)
        let menu = NSMenu(title: "DynamicNotch")
        let settingsItem = NSMenuItem(
            title: NSLocalizedString("Settings…", comment: "Status menu item that opens the settings window"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: NSLocalizedString("Quit DynamicNotch", comment: "Status menu item that quits the app"),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        statusItem?.menu = menu
    }

    // Opens settings/preferences window
    @objc private func openSettings() {
        // Show NookSettingsView in a window
        WindowsManager.shared.showSettings()
    }
}