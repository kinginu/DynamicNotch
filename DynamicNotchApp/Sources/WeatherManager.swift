// Data source of the Weather widget (2026-10-20).
//
// WeatherKit needs a paid developer team (this app is ad-hoc signed), so the forecast comes from
// the free, key-less Open-Meteo API (https://open-meteo.com — free for non-commercial use, data
// CC BY 4.0, attribution shown in Settings ▸ Widgets ▸ Weather):
//   - forecast: https://api.open-meteo.com/v1/forecast — current temperature / WMO weather code /
//     day-night, 25 hourly slots (temperature, precipitation probability, weather code), today's
//     high / low; always in °C (the widget converts), times as unix seconds;
//   - city search: https://geocoding-api.open-meteo.com/v1/search.
// Location: the fixed city from the settings (default Tokyo), or CoreLocation when-in-use when the
// user picks "Current location" (the permission prompt is only shown from that choice; while access
// is not granted the fixed city is used). The last forecast is cached on disk
// (Application Support/<bundle id>/Weather/forecast.json): it is shown at launch and while offline,
// with its age. Refresh: every 15 minutes, on wake, when the location settings change, and from
// Settings ▸ Refresh Now; a failed fetch is retried after 2 minutes. The periodic / wake / retry
// refreshes run only while the widget is in the Nook or a Weather view (widget, settings) is shown.
import Foundation
import AppKit
import CoreLocation
import MapKit
import Observation

// MARK: - Model

struct WeatherForecast: Codable, Equatable {
    struct Hour: Codable, Equatable, Identifiable {
        var time: Date
        /// °C.
        var temperature: Double
        var precipitationProbability: Int?
        /// WMO weather interpretation code.
        var code: Int
        var isDay: Bool

        var id: Date { time }
    }

    var place: WeatherPlace
    /// The forecast was fetched for the device location (not the fixed city).
    var isCurrentLocation: Bool
    var fetchedAt: Date
    /// Offset of the place's time zone at fetch time (fallback for `timeZoneIdentifier`).
    var utcOffsetSeconds: Int
    /// IANA time zone of the place (hour labels are shown in the place's local time, with its DST
    /// rules). Optional: caches written before it existed still decode.
    var timeZoneIdentifier: String? = nil
    var current: Hour
    var hourly: [Hour]
    /// Today's high / low (°C) and code.
    var high: Double?
    var low: Double?

    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
    }

    /// "Now" followed by the next `count - 1` full hours.
    func strip(count: Int = 6, now: Date = Date()) -> [Hour] {
        let upcoming = hourly.filter { $0.time > now }
        return [Hour(time: now, temperature: current.temperature, precipitationProbability: hourly.last(where: { $0.time <= now })?.precipitationProbability,
                     code: current.code, isDay: current.isDay)]
            + upcoming.prefix(count - 1)
    }
}

/// Open-Meteo responses (only the fields used).
private struct OpenMeteoForecastResponse: Decodable {
    struct Current: Decodable {
        var time: TimeInterval
        var temperature_2m: Double?
        var weather_code: Int?
        var is_day: Int?
    }
    struct Hourly: Decodable {
        var time: [TimeInterval]
        var temperature_2m: [Double?]?
        var precipitation_probability: [Int?]?
        var weather_code: [Int?]?
        var is_day: [Int?]?
    }
    struct Daily: Decodable {
        var time: [TimeInterval]
        var temperature_2m_max: [Double?]?
        var temperature_2m_min: [Double?]?
    }
    var utc_offset_seconds: Int?
    /// IANA name of the place's zone (`timezone=auto`).
    var timezone: String?
    var current: Current?
    var hourly: Hourly?
    var daily: Daily?
}

private struct OpenMeteoErrorResponse: Decodable {
    var reason: String?
}

private struct OpenMeteoGeocodingResponse: Decodable {
    struct Result: Decodable {
        var name: String
        var latitude: Double
        var longitude: Double
        var country: String?
        var admin1: String?
    }
    var results: [Result]?
}

enum WeatherError: LocalizedError {
    case badResponse(Int)
    case api(String)
    case incomplete

    var errorDescription: String? {
        switch self {
        case .badResponse(let status): return String(localized: "The weather service returned an error (HTTP \(status)).")
        case .api(let reason): return reason
        case .incomplete: return String(localized: "The weather service returned incomplete data.")
        }
    }
}

// MARK: - Open-Meteo client

enum OpenMeteo {
    static let attributionURL = URL(string: "https://open-meteo.com/")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func forecast(for place: WeatherPlace, isCurrentLocation: Bool) async throws -> WeatherForecast {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", place.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "forecast_hours", value: "25"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        let data = try await get(c.url!)
        let r = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        guard let cur = r.current, let temp = cur.temperature_2m, let code = cur.weather_code, let h = r.hourly else {
            throw WeatherError.incomplete
        }
        var hours: [WeatherForecast.Hour] = []
        for (i, t) in h.time.enumerated() {
            guard let temp = h.temperature_2m?[safe: i] ?? nil, let code = h.weather_code?[safe: i] ?? nil else { continue }
            hours.append(.init(time: Date(timeIntervalSince1970: t), temperature: temp,
                               precipitationProbability: h.precipitation_probability?[safe: i] ?? nil,
                               code: code, isDay: (h.is_day?[safe: i] ?? nil) != 0))
        }
        // today = the daily entry whose local midnight is the latest one not after now
        let now = Date().timeIntervalSince1970
        let todayIndex = r.daily?.time.lastIndex(where: { $0 <= now }) ?? 0
        return WeatherForecast(
            place: place, isCurrentLocation: isCurrentLocation, fetchedAt: Date(),
            utcOffsetSeconds: r.utc_offset_seconds ?? TimeZone.current.secondsFromGMT(),
            timeZoneIdentifier: r.timezone,
            current: .init(time: Date(timeIntervalSince1970: cur.time), temperature: temp, precipitationProbability: nil,
                           code: code, isDay: (cur.is_day ?? 1) != 0),
            hourly: hours,
            high: r.daily?.temperature_2m_max?[safe: todayIndex] ?? nil,
            low: r.daily?.temperature_2m_min?[safe: todayIndex] ?? nil)
    }

    static func searchCities(_ query: String) async throws -> [WeatherPlace] {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            .init(name: "name", value: query),
            .init(name: "count", value: "8"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json"),
        ]
        let data = try await get(c.url!)
        let r = try JSONDecoder().decode(OpenMeteoGeocodingResponse.self, from: data)
        return (r.results ?? []).map {
            WeatherPlace(name: $0.name, region: $0.admin1, country: $0.country, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private static func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if let reason = (try? JSONDecoder().decode(OpenMeteoErrorResponse.self, from: data))?.reason {
                throw WeatherError.api(reason)
            }
            throw WeatherError.badResponse(status)
        }
        return data
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Manager

@MainActor
@Observable
final class WeatherManager {
    static let shared = WeatherManager()

    static let refreshInterval: TimeInterval = 15 * 60
    static let retryInterval: TimeInterval = 2 * 60

    enum LocationAccess: Equatable {
        case notDetermined, authorized, denied, restricted
        /// Authorized, but no fix could be obtained (Location Services off / no Wi-Fi).
        case unavailable
    }

    /// Last forecast (from the network or the disk cache).
    private(set) var forecast: WeatherForecast?
    private(set) var isLoading = false
    /// Message of the last failed fetch (nil after a success).
    private(set) var lastError: String?
    private(set) var locationAccess: LocationAccess = .notDetermined
    /// "Current location" is selected but the fixed city is shown (access not granted / no fix).
    private(set) var usingFallbackCity = false

    /// The periodic / wake / retry refreshes run while the widget is in the Nook or a Weather view
    /// (widget instances, the settings pane) is shown.
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(.weather, label: "Weather",
                                      onNeeded: { [unowned self] in self.installTimer() },
                                      onIdle: { [unowned self] in self.tearDown() })
        // give the network a moment to come back after wake
        presence.onWake(after: 4) { [unowned self] in self.refresh(force: true) }
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in self.timer != nil || self.retryTask != nil }
        #endif
        return presence
    }()
    /// Periodic refresh installed (the widget is in the Nook or a Weather view is shown).
    private var started: Bool { presence.isActive }
    /// `locationAccess` when the fallback city was last fetched for "Current location" (nil otherwise).
    @ObservationIgnored private var fallbackAccess: LocationAccess?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private let locator = WeatherLocator()

    private init() {
        forecast = Self.loadCache()
        locationAccess = locator.access
        locator.onAuthorizationChange = { [weak self] access in
            guard let self else { return }
            let wasAuthorized = self.locationAccess == .authorized
            self.locationAccess = access
            if access == .authorized, !wasAuthorized, self.started, self.settings.locationMode == .current {
                self.refresh(force: true)
            }
        }
    }

    private var settings: WeatherWidgetSettings { SettingsStore[.weatherWidgetSettings] }

    /// A Weather view (widget or settings) appeared: refreshes if stale and keeps the periodic
    /// refresh running. Balanced by `stop()` from the view's onDisappear.
    func start() {
        #if DEBUG
        WeatherDebug.install()
        #endif
        presence.setVisible(true)
        refresh(force: false)
    }

    /// A Weather view disappeared. Refreshing continues while the widget is in the Nook (so the
    /// closed-notch-to-open transition shows a fresh forecast) and stops once it was removed.
    func stop() {
        presence.setVisible(false)
    }

    /// Same as `start()` / `stop()`.
    func setVisible(_ visible: Bool) {
        if visible { start() } else { stop() }
    }

    private func installTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                WeatherManager.shared.presence.debugCheckTick()
                WeatherManager.shared.refresh(force: false)
            }
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        retryTask?.cancel()
        retryTask = nil
        // an in-flight fetch is left to finish (one request; its result is cached)
    }

    /// The location settings changed: fetch for the new place right away.
    func settingsChanged() {
        refresh(force: false)
    }

    /// Shows the when-in-use permission prompt (only from the "Current location" choice).
    func requestLocationAccess() {
        locator.requestAuthorization()
        locationAccess = locator.access
    }

    /// Age of the shown forecast.
    var age: TimeInterval? { forecast.map { Date().timeIntervalSince($0.fetchedAt) } }

    /// Fetches unless the cached forecast is for the wanted place and younger than 15 minutes.
    func refresh(force: Bool) {
        guard fetchTask == nil else { return }
        let settings = self.settings
        let wantsCurrent = settings.locationMode == .current
        let access = locator.access
        // authorized but the last attempt got no fix: keep showing that until the next attempt
        locationAccess = wantsCurrent && usingFallbackCity && fallbackAccess == .unavailable && access == .authorized
            ? .unavailable : access
        if !force, let forecast, Date().timeIntervalSince(forecast.fetchedAt) < Self.refreshInterval - 30 {
            let placeMatches: Bool
            if !wantsCurrent {
                placeMatches = !forecast.isCurrentLocation && Self.isNear(forecast.place, settings.city)
            } else if forecast.isCurrentLocation {
                placeMatches = access == .authorized
            } else {
                // "Current location" without a usable location: the fallback city counts as fresh
                // for the interval too, unless the access changed since (granted → fetch now)
                placeMatches = usingFallbackCity && Self.isNear(forecast.place, settings.city)
                    && locationAccess == fallbackAccess
            }
            if placeMatches { return }
        }
        isLoading = true
        fetchTask = Task { @MainActor in
            defer { self.isLoading = false; self.fetchTask = nil }
            var place = settings.city
            var isCurrent = false
            if wantsCurrent, locator.access == .authorized {
                if let found = await locator.currentPlace(reusing: forecast?.isCurrentLocation == true ? forecast?.place : nil) {
                    place = found
                    isCurrent = true
                    locationAccess = locator.access
                } else {
                    locationAccess = locator.access == .authorized ? .unavailable : locator.access
                }
            }
            usingFallbackCity = wantsCurrent && !isCurrent
            fallbackAccess = usingFallbackCity ? locationAccess : nil
            do {
                let fresh = try await OpenMeteo.forecast(for: place, isCurrentLocation: isCurrent)
                forecast = fresh
                lastError = nil
                retryTask?.cancel(); retryTask = nil
                Self.saveCache(fresh)
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                NSLog("[Weather] fetch failed: %@", "\(error)")
                scheduleRetry()
            }
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil, started else { return }
        retryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.retryInterval))
            guard !Task.isCancelled else { return }
            self.retryTask = nil
            self.refresh(force: true)
        }
    }

    /// Same place within ~5 km (geocoding results and saved cities are compared by coordinates).
    static func isNear(_ a: WeatherPlace, _ b: WeatherPlace) -> Bool {
        abs(a.latitude - b.latitude) < 0.05 && abs(a.longitude - b.longitude) < 0.05
    }

    // MARK: Disk cache

    private static var cacheURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "DynamicNotch", isDirectory: true)
            .appendingPathComponent("Weather", isDirectory: true)
            .appendingPathComponent("forecast.json")
    }

    private static func loadCache() -> WeatherForecast? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WeatherForecast.self, from: data)
    }

    private static func saveCache(_ forecast: WeatherForecast) {
        guard let url = cacheURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(forecast).write(to: url, options: .atomic)
        } catch {
            NSLog("[Weather] cache write failed: %@", "\(error)")
        }
    }

    #if DEBUG
    /// DEBUG previews: replaces the shown forecast without fetching or caching.
    func debugSetForecast(_ forecast: WeatherForecast?, error: String?) {
        self.forecast = forecast
        self.lastError = error
    }
    #endif
}

// MARK: - CoreLocation

/// One-shot when-in-use location fixes + reverse geocoding (MapKit) for the place name.
@MainActor
private final class WeatherLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: [CheckedContinuation<CLLocation?, Never>] = []
    var onAuthorizationChange: ((WeatherManager.LocationAccess) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var access: WeatherManager.LocationAccess {
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        default: return CLLocationManager.locationServicesEnabled() ? .authorized : .denied
        }
    }

    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// The device location as a place (named by reverse geocoding; `reusing`'s name is kept when
    /// the device has not moved more than ~5 km).
    func currentPlace(reusing previous: WeatherPlace?) async -> WeatherPlace? {
        guard let location = await fix() else { return nil }
        var place = WeatherPlace(name: String(localized: "Current Location"),
                                 latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        if let previous, WeatherManager.isNear(previous, place), previous.name != place.name {
            place.name = previous.name
            place.region = previous.region
            place.country = previous.country
            return place
        }
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first {
            if let city = item.addressRepresentations?.cityName, !city.isEmpty {
                place.name = city
            } else if let name = item.name, !name.isEmpty {
                place.name = name
            }
            place.region = item.addressRepresentations?.regionName
        }
        return place
    }

    private func fix() async -> CLLocation? {
        await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            pending.append(c)
            if pending.count == 1 { manager.requestLocation() }
        }
    }

    private func finish(_ location: CLLocation?) {
        let waiting = pending
        pending.removeAll()
        for c in waiting { c.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated { finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[Weather] location failed: %@", "\(error)")
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            onAuthorizationChange?(access)
        }
    }
}
