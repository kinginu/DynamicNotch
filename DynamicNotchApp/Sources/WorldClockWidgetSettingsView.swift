// Settings ▸ Nook ▸ Widgets ▸ World Clock (2026-10-20): the clocks (label override, reorder,
// remove), adding a time zone (search over TimeZone.knownTimeZoneIdentifiers), and display options
// (seconds, 12/24-hour, analog dial, day/night tint).
import SwiftUI

struct WorldClockWidgetSettingsView: View {
    @StoredSetting(.worldClocksWidgetSettings) private var settings
    @State private var query = ""

    var body: some View {
        SettingsForm {
            Section {
                if settings.clocks.isEmpty {
                    Text("No clocks").foregroundStyle(.secondary)
                }
                ForEach(Array(settings.clocks.enumerated()), id: \.element.id) { index, clock in
                    WorldClockSettingsRow(
                        clock: clock,
                        label: Binding(
                            get: { settings.clocks.first { $0.id == clock.id }?.label ?? "" },
                            set: { value in
                                if let i = settings.clocks.firstIndex(where: { $0.id == clock.id }) {
                                    settings.clocks[i].label = value
                                }
                            }
                        ),
                        canMoveUp: index > 0,
                        canMoveDown: index < settings.clocks.count - 1,
                        move: { delta in move(clock, by: delta) },
                        remove: { settings.clocks.removeAll { $0.id == clock.id } }
                    )
                }
                .onMove { from, to in settings.clocks.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("Clocks")
            } footer: {
                Text("Labels of up to 4 characters are shown as typed; longer names are abbreviated (Tokyo → TOK, New York → NY).")
                    .settingsFootnote()
            }

            Section("Add a Clock") {
                if settings.clocks.count >= WorldClockWidgetSettings.maxClocks {
                    Text("The widget holds up to \(WorldClockWidgetSettings.maxClocks) clocks.")
                        .foregroundStyle(.secondary)
                } else {
                    if !settings.clocks.contains(where: \.isLocal) {
                        Button("Add This Mac’s Time Zone") { add(WorldClock.localID) }
                    }
                    TextField("Search", text: $query, prompt: Text("City or time zone"))
                    let results = WorldClockZoneSearch.results(for: query)
                    if !query.isEmpty, results.isEmpty {
                        Text("No matching time zones").foregroundStyle(.secondary)
                    }
                    ForEach(results, id: \.self) { identifier in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: WorldClock.cityName(of: identifier))
                                Text(verbatim: WorldClockZoneSearch.subtitle(for: identifier))
                                    .settingsFootnote()
                            }
                            Spacer()
                            Button {
                                add(identifier)
                            } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(Color.green)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Add"))
                        }
                    }
                }
            }

            Section("Display") {
                Toggle("Show seconds", isOn: $settings.showSeconds)
                Picker("Time format", selection: $settings.hourFormat) {
                    Text("System").tag(WorldClockWidgetSettings.HourFormat.system)
                    Text("12-hour").tag(WorldClockWidgetSettings.HourFormat.twelveHour)
                    Text("24-hour").tag(WorldClockWidgetSettings.HourFormat.twentyFourHour)
                }
                Toggle("Show analog dial", isOn: $settings.showAnalogDial)
                Toggle("Light tile during the day", isOn: $settings.tintByDaytime)
            }
        }
    }

    private func add(_ identifier: String) {
        guard settings.clocks.count < WorldClockWidgetSettings.maxClocks else { return }
        settings.clocks.append(WorldClock(timeZoneID: identifier))
        query = ""
    }

    private func move(_ clock: WorldClock, by delta: Int) {
        guard let i = settings.clocks.firstIndex(where: { $0.id == clock.id }) else { return }
        let j = i + delta
        guard settings.clocks.indices.contains(j) else { return }
        settings.clocks.swapAt(i, j)
    }
}

private struct WorldClockSettingsRow: View {
    let clock: WorldClock
    @Binding var label: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: clock.shortLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 36, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            VStack(alignment: .leading, spacing: 2) {
                TextField("Label", text: $label, prompt: Text(verbatim: WorldClock.cityName(of: clock.timeZone.identifier)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Text(verbatim: subtitle)
                    .settingsFootnote()
            }
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help(String(localized: "Move Up"))
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help(String(localized: "Move Down"))
            SettingsRemoveButton(action: remove)
        }
    }

    private var subtitle: String {
        let zone = WorldClockZoneSearch.subtitle(for: clock.timeZone.identifier)
        return clock.isLocal ? String(localized: "This Mac") + " · " + zone : zone
    }
}

/// Search over `TimeZone.knownTimeZoneIdentifiers` (identifier, city and localized zone name).
enum WorldClockZoneSearch {
    static let maxResults = 30

    private static let identifiers: [String] = TimeZone.knownTimeZoneIdentifiers.sorted {
        WorldClock.cityName(of: $0).localizedStandardCompare(WorldClock.cityName(of: $1)) == .orderedAscending
    }

    static func results(for query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let normalized = q.replacingOccurrences(of: " ", with: "_")
        var prefix: [String] = [], other: [String] = []
        for id in identifiers {
            let city = WorldClock.cityName(of: id)
            if city.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                prefix.append(id)
            } else if id.range(of: normalized, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                        || (TimeZone(identifier: id)?.localizedName(for: .generic, locale: .autoupdatingCurrent)?
                            .range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil) {
                other.append(id)
            }
            if prefix.count >= maxResults { break }
        }
        return Array((prefix + other).prefix(maxResults))
    }

    /// "Asia/Tokyo · Japan Standard Time · GMT+9".
    static func subtitle(for identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        var parts = [identifier]
        if let name = zone.localizedName(for: .generic, locale: .autoupdatingCurrent) { parts.append(name) }
        let seconds = zone.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "\u{2212}"
        let minutes = abs(seconds) / 60
        parts.append(minutes % 60 == 0 ? "GMT\(sign)\(minutes / 60)" : String(format: "GMT%@%d:%02d", sign, minutes / 60, minutes % 60))
        return parts.joined(separator: " · ")
    }
}
