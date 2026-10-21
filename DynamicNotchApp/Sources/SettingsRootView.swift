// Native SwiftUI settings window (replaces sindresorhus/Settings).
//
// App/DynamicNotchApp.swift declares `Settings { SettingsRootView() }`; this file holds the
// window's content (one toolbar tab per pane, in the order the old SettingsWindowController
// used) and the shared pane selection. `WindowsManager.showSettings(pane:)` sets the selection
// and opens the window (WindowsManager.swift, `SettingsWindowOpener`).
//
// `AppSettings.PaneIdentifier` keeps the spelling of the sindresorhus/Settings API it replaces
// (`AppSettings.PaneIdentifier("nook")`), so the existing call sites (notch "Open Settings"
// buttons, DebugHooks `settings:<paneId>`, fan-control-integration.md (d)) keep working unchanged.
import SwiftUI
import Observation

enum AppSettings {
    /// Identifier of one settings tab ("general", "nook", …, "fanControl", "about").
    struct PaneIdentifier: Hashable, RawRepresentable, Sendable {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        init(_ rawValue: String) { self.rawValue = rawValue }
    }
}

extension AppSettings.PaneIdentifier {
    static let general = Self("general")
    static let nook = Self("nook")
    static let liveActivities = Self("liveActivities")
    static let tray = Self("tray")
    static let liquidGlass = Self("liquidGlass")
    static let gestures = Self("gestures")
    static let about = Self("about")
    // `.fanControl` is declared by fan-control-integration.md (d) (Support/FanControl-Patches.swift).
}

/// Selected settings tab, shared by the window and by `WindowsManager.showSettings(pane:)`.
/// Persisted so the window reopens on the last tab (like System Settings).
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    private static let defaultsKey = "settingsSelectedPane"

    var pane: AppSettings.PaneIdentifier {
        didSet { UserDefaults.standard.set(pane.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        pane = UserDefaults.standard.string(forKey: Self.defaultsKey).map { AppSettings.PaneIdentifier($0) } ?? .general
    }
}

/// Content of the `Settings` scene: a toolbar-style `TabView` with one tab per pane.
struct SettingsRootView: View {
    /// Every tab gets this exact size, so switching tabs never resizes the window. 760 × 640 fits
    /// the largest pane (Fan Control: 740 × 600 inside its own padding; LiquidSettingsView: 608 × 640).
    /// Panes whose content can be taller scroll inside their own Form / ScrollView.
    static let contentSize = CGSize(width: 760, height: 640)

    @State private var navigation = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $navigation.pane) {
            tab(.general, "General", "gearshape") { GeneralSettingsView() }
            tab(.nook, "Nook", "rectangle.topthird.inset.filled") { NookSettingsView() }
            tab(.liveActivities, "Live Activities", "waveform") { LiveActivitiesSettingsView() }
            tab(.tray, "Tray", "tray") { TraySettingsView() }
            tab(.liquidGlass, "Liquid Glass", "drop") { LiquidSettingsView() }
            tab(.gestures, "Gestures", "hand.draw") { GesturesSettingsView() }
            #if canImport(FanControlKit) // fan-control-integration.md (d): before About
            tab(.fanControl, "Fan Control", "fan") { FanControlSettingsView() }
            tab(.powerProfiles, "Power Profiles", "bolt.badge.automatic") { FanControlPowerProfilesSettingsView() } // F2
            #endif
            tab(.about, "About", "info.circle") { AboutSettingsView() }
        }
    }

    private func tab<Content: View>(
        _ id: AppSettings.PaneIdentifier, _ title: LocalizedStringKey, _ symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .top)
            .tabItem { Label(title, systemImage: symbol) }
            .tag(id)
    }
}

/// Sub-tabs inside one settings tab (Nook, Live Activities). A nested `TabView` cannot be used:
/// inside the `Settings` scene SwiftUI hoists every `TabView`'s items into the window toolbar
/// (and takes the window title from the inner tab), so sub-tabs are a centred segmented control
/// above the content instead.
struct SettingsSubTabs<Selection: Hashable, Content: View>: View {
    @Binding var selection: Selection
    let tabs: [(Selection, LocalizedStringKey)]
    @ViewBuilder var content: (Selection) -> Content

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(tabs, id: \.0) { tab in
                    Text(tab.1).tag(tab.0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 12)
            .padding(.bottom, 4)

            content(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
