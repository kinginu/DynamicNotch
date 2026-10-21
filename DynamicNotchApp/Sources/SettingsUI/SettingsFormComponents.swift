// Shared building blocks of the settings panes (Settings ▸ every tab, Settings ▸ Nook ▸ Widgets ▸ …),
// so every pane has the same Apple-native look: a grouped `Form` that scrolls inside the fixed
// 760 × 640 tab (`SettingsRootView.contentSize`), caption footnotes, section headers with trailing
// buttons, choice pickers that keep a hand-edited stored value selectable, app and item rows.
//
// Permission rows are in PermissionStatusRow.swift, the data attribution section in
// SettingsAttributionSection.swift.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Pane container

/// The container of one settings pane: a grouped `Form`. It fills the space it is given and
/// scrolls its own content, so panes never resize the settings window (the tab frames every pane
/// at `SettingsRootView.contentSize`) and never need an outer `ScrollView`.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Text styles

extension View {
    /// Footnote style of the panes: section footers and the explanation under a control
    /// (caption, secondary). Apply to a `Text` or to a stack of them.
    func settingsFootnote() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}

/// A section header with trailing buttons ("Calendars ··· Select All", "Presets ··· Restore Defaults").
struct SettingsSectionHeader<Accessory: View>: View {
    private let title: Text
    private let accessory: Accessory

    init(_ title: LocalizedStringKey, @ViewBuilder accessory: () -> Accessory) {
        self.title = Text(title)
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            title
            Spacer()
            accessory
        }
    }
}

// MARK: - Choice pickers

extension Array where Element: Comparable {
    /// The offered choices plus `current` when it is not one of them (a stored value edited by
    /// hand or an older default), sorted, so the picker still shows the stored value.
    func settingsChoices(including current: Element) -> [Element] {
        contains(current) ? self : (self + [current]).sorted()
    }
}

/// A menu picker over fixed choices that keeps a stored value outside `choices` selectable
/// (`settingsChoices(including:)`). `label` gives the text of one choice.
struct SettingsChoicePicker<Value: Hashable & Comparable>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Value
    private let choices: [Value]
    private let label: (Value) -> Text

    init(_ title: LocalizedStringKey, selection: Binding<Value>, choices: [Value],
         label: @escaping (Value) -> Text) {
        self.title = title
        self._selection = selection
        self.choices = choices
        self.label = label
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices.settingsChoices(including: selection), id: \.self) { value in
                label(value).tag(value)
            }
        }
    }
}

// MARK: - Rows

/// A list row with a leading SF Symbol (fixed width, secondary), a title and trailing content:
/// the device / volume / item rows of the Audio, Bluetooth, Batteries and Storage panes.
struct SettingsSymbolRow<Title: View, Trailing: View>: View {
    private let systemImage: String
    private let title: Title
    private let trailing: Trailing

    init(systemImage: String, @ViewBuilder title: () -> Title, @ViewBuilder trailing: () -> Trailing) {
        self.systemImage = systemImage
        self.title = title()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            title
            Spacer()
            trailing
        }
    }
}

extension SettingsSymbolRow where Trailing == EmptyView {
    init(systemImage: String, @ViewBuilder title: () -> Title) {
        self.init(systemImage: systemImage, title: title, trailing: { EmptyView() })
    }
}

/// The label of a calendar / Reminders list toggle: colour dot, title, account (secondary).
struct SettingsCalendarLabel: View {
    let color: Color
    let title: String
    let source: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(verbatim: title)
            Text(verbatim: source).foregroundStyle(.secondary)
        }
    }
}

/// Count of saved items and a destructive "Clear History" button (Clipboard, Color Picker,
/// Calculator).
struct SettingsHistoryRow: View {
    /// Localized summary ("12 items in history").
    let summary: String
    let clearTitle: LocalizedStringKey
    let isEmpty: Bool
    let clear: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: summary)
                .foregroundStyle(.secondary)
            Spacer()
            Button(clearTitle, role: .destructive, action: clear)
                .disabled(isEmpty)
        }
    }
}

/// The red minus button that removes a row from a list (help: "Remove").
struct SettingsRemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(Color.red.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help(String(localized: "Remove"))
    }
}

// MARK: - Apps

/// Apps referenced by bundle identifier in the settings (excluded apps, always-shown apps).
enum SettingsApps {
    static func url(of bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Display name of an app file ("Safari"), without the ".app" extension.
    static func name(atPath path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }


    static func name(of bundleID: String) -> String {
        url(of: bundleID).map { name(atPath: $0.path) } ?? bundleID
    }

    /// Asks for one or more apps (open panel in /Applications) and returns their bundle identifiers.
    @MainActor
    static func chooseBundleIDs() -> [String] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }
}


struct SettingsAppIcon: View {
    let bundleID: String?
    var fallbackSymbol = "app.dashed"

    var body: some View {
        if let bundleID, let url = SettingsApps.url(of: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: fallbackSymbol)
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
        }
    }
}
