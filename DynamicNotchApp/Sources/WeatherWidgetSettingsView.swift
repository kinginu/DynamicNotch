// Settings of the Weather widget (Settings ▸ Nook ▸ Widgets ▸ Weather): location mode (fixed
// city / current location), city search (Open-Meteo geocoding), °C / °F, hourly strip on/off,
// refresh status, and the Open-Meteo attribution (required by its terms: free for non-commercial
// use, data under CC BY 4.0).
import SwiftUI

struct WeatherWidgetSettingsView: View {
    @StoredSetting(.weatherWidgetSettings) private var settings
    @State private var manager = WeatherManager.shared
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        SettingsForm {
            locationSection
            if settings.locationMode == .city {
                citySection
            }
            Section {
                Picker("Temperature unit", selection: $settings.unit) {
                    Text("Celsius (°C)").tag(WeatherWidgetSettings.TemperatureUnit.celsius)
                    Text("Fahrenheit (°F)").tag(WeatherWidgetSettings.TemperatureUnit.fahrenheit)
                }
                Toggle("Show hourly forecast", isOn: $settings.showHourly)
            } header: {
                Text("Display")
            }
            statusSection
            SettingsAttributionSection(
                prefix: "Weather data by",
                provider: "Open-Meteo.com",
                url: OpenMeteo.attributionURL,
                terms: "Open-Meteo is free for non-commercial use; its data is licensed under CC BY 4.0. No API key or account is used, and only the forecast location is sent.")
        }
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
        .onChange(of: settings.locationMode) { _, mode in
            if mode == .current { manager.requestLocationAccess() }
            manager.settingsChanged()
        }
        .onChange(of: settings.city) { _, _ in manager.settingsChanged() }
        .task(id: query) { await search() }
    }

    // MARK: Location

    private var locationSection: some View {
        Section {
            Picker("Location", selection: $settings.locationMode) {
                Text("City").tag(WeatherWidgetSettings.LocationMode.city)
                Text("Current location").tag(WeatherWidgetSettings.LocationMode.current)
            }
            .pickerStyle(.segmented)
            if settings.locationMode == .current {
                locationAccessRow
            }
        } header: {
            Text("Location")
        } footer: {
            if settings.locationMode == .current {
                Text("Your location is only used to fetch the forecast. While location access is unavailable, the widget shows \(settings.city.detail).")
                    .settingsFootnote()
            }
        }
    }

    /// The manager's status: `.unavailable` there means access is on but no fix was obtained.
    private var locationAccessRow: some View {
        PermissionStatusRow(
            kind: .location,
            status: locationStatus,
            granted: "Location access is on.",
            notDetermined: "DynamicNotch needs permission to use your location.",
            denied: "Location access is off. Turn on DynamicNotch in System Settings ▸ Privacy & Security ▸ Location Services.",
            unavailable: "Your location could not be determined.",
            allowTitle: "Allow Location Access",
            allow: { manager.requestLocationAccess() })
    }

    private var locationStatus: PermissionStatus {
        switch manager.locationAccess {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .unavailable: return .unavailable
        }
    }

    // MARK: City

    private var citySection: some View {
        Section {
            LabeledContent("City") {
                Text(settings.city.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            TextField("Search city", text: $query, prompt: Text("City name"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
            if searching {
                ProgressView().controlSize(.small)
            } else if let searchError {
                Text(searchError)
                    .settingsFootnote()
            } else if !trimmedQuery.isEmpty && results.isEmpty {
                Text("No matching cities")
                    .settingsFootnote()
            }
            ForEach(results) { place in
                Button {
                    settings.city = place
                    query = ""
                    results = []
                } label: {
                    HStack {
                        Image(systemName: WeatherManager.isNear(place, settings.city) ? "checkmark.circle.fill" : "mappin.circle")
                            .foregroundStyle(WeatherManager.isNear(place, settings.city) ? Color.accentColor : .secondary)
                        Text(place.detail)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(String(format: "%.2f, %.2f", place.latitude, place.longitude))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("City")
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func search() async {
        let q = trimmedQuery
        searchError = nil
        guard q.count >= 2 else { results = []; searching = false; return }
        try? await Task.sleep(for: .milliseconds(350)) // debounce typing
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let found = try await OpenMeteo.searchCities(q)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let f = manager.forecast {
                        Text("Updated \(f.fetchedAt.formatted(date: .abbreviated, time: .shortened)) for \(f.place.name)")
                    } else {
                        Text("No weather data yet")
                    }
                    if let error = manager.lastError {
                        Text(error)
                            .settingsFootnote()
                    }
                }
                Spacer()
                if manager.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh Now") { manager.refresh(force: true) }
                    .disabled(manager.isLoading)
            }
        } footer: {
            Text("The forecast refreshes every 15 minutes and after the Mac wakes. When offline, the last forecast is shown with its age.")
                .settingsFootnote()
        }
    }
}
