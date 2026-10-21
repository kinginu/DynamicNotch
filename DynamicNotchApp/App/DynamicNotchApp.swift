// App entry point of DynamicNotch.
//
// The `@main` entry lives here, outside Sources/, so only the Xcode app target compiles it
// (project.yml); the Command Line Tools harness builds Sources/ as a library.
//
// The app is an agent (LSUIElement): AppDelegate sets up the status item and the notch
// windows. The settings window is SwiftUI's native `Settings` scene (toolbar tabs, one per
// pane; Sources/SettingsRootView.swift). AppKit code opens it through
// `WindowsManager.showSettings(pane:)` (Sources/WindowsManager.swift).
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
        }
    }
}
