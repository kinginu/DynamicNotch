// Settings ▸ Nook ▸ Widgets ▸ Usage (2026-10-20): recording on/off (off by default, with a
// privacy note), idle threshold, excluded apps, CSV export (NSSavePanel) and clearing the data.
// Built from SettingsUI (SettingsForm, settingsFootnote, SettingsChoicePicker, SettingsApps /
// SettingsAppIcon / SettingsRemoveButton, SettingsHistoryRow).
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct UsageWidgetSettingsView: View {
    @StoredSetting(.usageWidgetSettings) private var settings
    @State private var tracker = UsageTracker.shared
    @State private var confirmClear = false
    @State private var exportError: String?

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Record app usage", isOn: $settings.trackingEnabled)
            } footer: {
                Text("When on, DynamicNotch records which app is in front and for how long, and how often this Mac is unlocked. The data stays on this Mac, is never sent anywhere, and daily totals older than 90 days are deleted.")
                    .settingsFootnote()
            }

            Section {
                SettingsChoicePicker("Stop counting after", selection: $settings.idleThreshold,
                                     choices: UsageWidgetSettings.idleThresholdChoices) { s in
                    Text(Duration.seconds(s), format: .units(allowed: [.minutes, .seconds], width: .wide))
                }
            } footer: {
                Text("Time without keyboard, mouse or trackpad input is not counted. Time while this Mac is asleep or locked is never counted.")
                    .settingsFootnote()
            }

            Section {
                if settings.excludedAppIDs.isEmpty {
                    Text("No excluded apps").foregroundStyle(.secondary)
                }
                ForEach(settings.excludedAppIDs, id: \.self) { id in
                    HStack(spacing: 8) {
                        SettingsAppIcon(bundleID: id)
                        Text(verbatim: SettingsApps.name(of: id))
                        Spacer()
                        SettingsRemoveButton { settings.excludedAppIDs.removeAll { $0 == id } }
                    }
                }
                Menu("Add App") {
                    let candidates = tracker.recentApps().filter { !settings.excludedAppIDs.contains($0.appID) }
                    if !candidates.isEmpty {
                        Section("Recently Used") {
                            ForEach(candidates.prefix(12)) { app in
                                Button(app.appName.isEmpty ? app.appID : app.appName) { exclude(app.appID) }
                            }
                        }
                    }
                    Button("Choose App…") { SettingsApps.chooseBundleIDs().forEach(exclude) }
                }
                .fixedSize()
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("Excluded apps are not recorded, and what was recorded for them before is hidden.")
                    .settingsFootnote()
            }

            Section("Data") {
                let recorded = UsageStore.shared.recordedDays
                SettingsHistoryRow(summary: Self.recordedSummary(recorded), clearTitle: "Clear Usage Data…",
                                   isEmpty: recorded.count == 0) { confirmClear = true }
                Button("Export CSV…") { exportCSV() }
                    .disabled(recorded.count == 0)
                if let exportError {
                    Text(verbatim: exportError).font(.caption).foregroundStyle(.red)
                }
            }
            // re-read the counts after every save
            .id(tracker.revision)
        }
        .confirmationDialog("Clear all usage data?", isPresented: $confirmClear) {
            Button("Clear Usage Data", role: .destructive) { tracker.clearAllData() }
        } message: {
            Text("This deletes every recorded day on this Mac. It cannot be undone.")
        }
    }

    static func recordedSummary(_ recorded: (count: Int, first: UsageDay?)) -> String {
        guard let first = recorded.first else { return String(localized: "Nothing recorded yet") }
        return String(format: String(localized: "%lld days recorded since %@"), recorded.count,
                      first.start(in: .current).formatted(date: .abbreviated, time: .omitted))
    }

    private func exclude(_ id: String) {
        guard !settings.excludedAppIDs.contains(id) else { return }
        settings.excludedAppIDs.append(id)
    }

    private func exportCSV() {
        exportError = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Usage \(UsageDay(Date(), calendar: .current).key).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tracker.csv().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
