import AppKit
import SwiftUI

extension WindowsManager {
    /// Called once at launch (AppDelegate). The settings window itself is SwiftUI's native
    /// `Settings` scene (App/DynamicNotchApp.swift → `SettingsRootView`), created lazily by
    /// SwiftUI the first time it is opened, so there is nothing to assemble here any more.
    func setupSettingsWindow() {}
}

/// Opens the native `Settings` scene from AppKit code (status-item menu, notch buttons,
/// DebugHooks). macOS 14+ ignores `NSApp.sendAction(Selector(("showSettingsWindow:")), …)`, and
/// SwiftUI's `OpenSettingsAction` (`@Environment(\.openSettings)`) is shadowed in this module by the
/// app's own `EnvironmentValues.openSettings: () -> Void` (Support/EnvironmentValues+Notch.swift).
/// So the app menu's "Settings…" item, which SwiftUI adds for the `Settings` scene and which
/// exists in an LSUIElement app too (verified on macOS 26.5), is invoked instead; the legacy
/// selector is only a last resort.
@MainActor
enum SettingsWindowOpener {
    /// The SwiftUI settings window, once it has been created.
    static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
    }

    static func open() {
        // LSUIElement agent: bring the app forward so the window is key and in front.
        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let item = settingsMenuItem, let menu = item.menu {
            menu.performActionForItem(at: menu.index(of: item))
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        // The window is created asynchronously; make sure it ends up in front.
        DispatchQueue.main.async {
            settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }

    /// The app menu's "Settings…" item that SwiftUI adds for a `Settings` scene (⌘,).
    private static var settingsMenuItem: NSMenuItem? {
        NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "," && $0.action != nil }
    }
}
