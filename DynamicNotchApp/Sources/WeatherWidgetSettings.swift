// Settings of the Weather widget (2026-10-20). Key "weatherWidgetSettings"
// (typed key still in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The forecast itself is cached in Application
// Support (WeatherManager), not here.
import Foundation

/// A place the forecast is fetched for (Open-Meteo geocoding result, or the device location).
struct WeatherPlace: Codable, Hashable, Identifiable {
    var name: String
    /// State / prefecture (geocoding `admin1`), if any.
    var region: String? = nil
    var country: String? = nil
    var latitude: Double
    var longitude: Double

    var id: String { String(format: "%.3f,%.3f", latitude, longitude) }

    /// "Tokyo, Japan" / "Springfield, Illinois, United States".
    var detail: String {
        [name, region == name ? nil : region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static let tokyo = WeatherPlace(name: "Tokyo", region: "Tokyo", country: "Japan", latitude: 35.6895, longitude: 139.69171)
}

struct WeatherWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    enum LocationMode: String, Codable, CaseIterable, Hashable {
        /// The fixed city chosen in the settings.
        case city
        /// CoreLocation (when-in-use); falls back to `city` when access is denied.
        case current
    }

    enum TemperatureUnit: String, Codable, CaseIterable, Hashable {
        case celsius, fahrenheit

        var symbol: String { self == .celsius ? "°C" : "°F" }

        /// Open-Meteo is always queried in °C; the widget converts.
        func convert(_ celsius: Double) -> Double {
            self == .celsius ? celsius : celsius * 9 / 5 + 32
        }
    }

    var locationMode: LocationMode = .city
    var city: WeatherPlace = .tokyo
    var unit: TemperatureUnit = Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    /// Show the six-slot hourly strip below the current conditions.
    var showHourly: Bool = true

    static let `default` = WeatherWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small } // width: NookWidgetLayout.cells (4 cells)

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.locationMode, into: &locationMode)
        c.decodeSetting(.city, into: &city)
        c.decodeSetting(.unit, into: &unit)
        c.decodeSetting(.showHourly, into: &showHourly)
    }

    private enum CodingKeys: String, CodingKey {
        case locationMode, city, unit, showHourly
    }
}
