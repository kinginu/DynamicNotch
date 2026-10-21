// Weather widget (2026-10-20), laid out like the small macOS Weather widget: place, big
// temperature, condition symbol + name, today's high / low, and a six-slot hourly strip (Now + the
// next five hours: hour, symbol, precipitation chance ≥ 30 %, temperature). 4 grid cells (200 pt).
// Data: WeatherManager (Open-Meteo). Offline / failed refreshes keep showing the cached forecast
// with its age in the top-right corner.
import SwiftUI
import AppKit

// MARK: - WMO weather codes

/// WMO weather interpretation codes (Open-Meteo `weather_code`) → SF Symbol and name.
enum WeatherCondition {
    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65: return "cloud.heavyrain.fill"
        case 71, 73, 75, 85, 86: return "cloud.snow.fill"
        case 77: return "snowflake"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 82: return "cloud.heavyrain.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func name(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? String(localized: "Sunny") : String(localized: "Clear")
        case 1: return isDay ? String(localized: "Mostly Sunny") : String(localized: "Mostly Clear")
        case 2: return String(localized: "Partly Cloudy")
        case 3: return String(localized: "Cloudy")
        case 45, 48: return String(localized: "Fog")
        case 51, 53, 55: return String(localized: "Drizzle")
        case 56, 57: return String(localized: "Freezing Drizzle")
        case 61, 63: return String(localized: "Rain")
        case 65: return String(localized: "Heavy Rain")
        case 66, 67: return String(localized: "Freezing Rain")
        case 71, 73: return String(localized: "Snow")
        case 75: return String(localized: "Heavy Snow")
        case 77: return String(localized: "Snow Grains")
        case 80, 81: return String(localized: "Showers")
        case 82: return String(localized: "Heavy Showers")
        case 85, 86: return String(localized: "Snow Showers")
        case 95: return String(localized: "Thunderstorms")
        case 96, 99: return String(localized: "Thunderstorms with Hail")
        default: return String(localized: "Unknown")
        }
    }
}

// MARK: - Widget

struct WeatherWidgetView: View {
    @State private var manager = WeatherManager.shared
    @StoredSetting(.weatherWidgetSettings) private var settings
    /// DEBUG previews: a fixed forecast / settings instead of the manager's and the stored ones.
    var previewForecast: WeatherForecast?? = nil
    var previewSettings: WeatherWidgetSettings? = nil
    var previewError: String? = nil
    var previewNow: Date? = nil

    private var shownSettings: WeatherWidgetSettings { previewSettings ?? settings }
    private var forecast: WeatherForecast? { previewForecast ?? manager.forecast }
    private var error: String? { previewForecast != nil ? previewError : manager.lastError }
    private var isPreview: Bool { previewForecast != nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: previewNow ?? context.date)
        }
        .nookWidgetFrame()
        .onAppear { if !isPreview { manager.start() } }
        .onDisappear { if !isPreview { manager.stop() } }
        .onChange(of: settings.locationMode) { _, _ in if !isPreview { manager.settingsChanged() } }
        .onChange(of: settings.city) { _, _ in if !isPreview { manager.settingsChanged() } }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let forecast {
            tile(forecast, now: now)
        } else if let error {
            NookWidgetEmptyState(
                systemImage: "cloud.sun",
                title: String(localized: "Weather unavailable"),
                message: error,
                actionTitle: isPreview ? nil : String(localized: "Retry"),
                action: isPreview ? nil : { manager.refresh(force: true) }
            )
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading weather…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func temperature(_ celsius: Double) -> String {
        "\(Int(shownSettings.unit.convert(celsius).rounded()))°"
    }

    private func tile(_ f: WeatherForecast, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(f, now: now)
            Text(temperature(f.current.temperature))
                .font(.system(size: shownSettings.showHourly ? 40 : 52, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.primary)
                .accessibilityLabel(Text("Temperature \(temperature(f.current.temperature))"))
            Spacer(minLength: 2)
            Image(systemName: WeatherCondition.symbol(code: f.current.code, isDay: f.current.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 15))
                .frame(height: 18)
                .accessibilityHidden(true)
            Text(WeatherCondition.name(code: f.current.code, isDay: f.current.isDay))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let high = f.high, let low = f.low {
                Text("H:\(temperature(high)) L:\(temperature(low))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if shownSettings.showHourly {
                hourlyStrip(f, now: now)
                    .padding(.top, 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius, style: .continuous)
                .fill(skyGradient(isDay: f.current.isDay, code: f.current.code))
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    private func header(_ f: WeatherForecast, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(f.place.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if f.isCurrentLocation {
                Image(systemName: "location.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .accessibilityLabel(Text("Current Location"))
            } else if shownSettings.locationMode == .current {
                Image(systemName: "location.slash")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Current location unavailable; showing the city from Settings."))
            }
            Spacer(minLength: 4)
            ageBadge(f, now: now)
        }
    }

    /// Age of the forecast when it is older than 30 minutes or the last refresh failed.
    @ViewBuilder
    private func ageBadge(_ f: WeatherForecast, now: Date) -> some View {
        let age = now.timeIntervalSince(f.fetchedAt)
        if age >= 30 * 60 || error != nil {
            HStack(spacing: 2) {
                if error != nil {
                    Image(systemName: "wifi.slash")
                }
                Text(Self.ageText(age))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(error.map { String(localized: "Showing saved weather. \($0)") } ?? String(localized: "Showing saved weather."))
        }
    }

    static func ageText(_ age: TimeInterval) -> String {
        let minutes = max(Int(age / 60), 0)
        if minutes < 1 { return String(localized: "now") }
        if minutes < 60 { return String(localized: "\(minutes)m ago") }
        let hours = minutes / 60
        if hours < 48 { return String(localized: "\(hours)h ago") }
        return String(localized: "\(hours / 24)d ago")
    }

    private func hourlyStrip(_ f: WeatherForecast, now: Date) -> some View {
        let hours = f.strip(count: 6, now: now)
        return HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                VStack(spacing: 3) {
                    Text(index == 0 ? String(localized: "Now") : Self.hourLabel(hour.time, in: f.timeZone))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: WeatherCondition.symbol(code: hour.code, isDay: hour.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 12))
                        .frame(height: 15)
                    Text(precipitationText(hour))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 1.0))
                        .frame(height: 9)
                    Text(temperature(hour.temperature))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func precipitationText(_ hour: WeatherForecast.Hour) -> String {
        guard let p = hour.precipitationProbability, p >= 30 else { return " " }
        return "\(p)%"
    }

    static func hourLabel(_ date: Date, in zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("j")
        return f.string(from: date).replacingOccurrences(of: " ", with: "")
    }

    /// A muted sky behind the tile (the notch stays dark): blue by day, indigo by night, grey for
    /// overcast / precipitation.
    private func skyGradient(isDay: Bool, code: Int) -> LinearGradient {
        let gloomy = code >= 3
        let colors: [Color]
        switch (isDay, gloomy) {
        case (true, false): colors = [Color(red: 0.20, green: 0.45, blue: 0.80), Color(red: 0.12, green: 0.30, blue: 0.62)]
        case (true, true): colors = [Color(red: 0.33, green: 0.40, blue: 0.50), Color(red: 0.20, green: 0.25, blue: 0.34)]
        case (false, false): colors = [Color(red: 0.10, green: 0.13, blue: 0.32), Color(red: 0.05, green: 0.07, blue: 0.18)]
        case (false, true): colors = [Color(red: 0.17, green: 0.19, blue: 0.27), Color(red: 0.08, green: 0.09, blue: 0.14)]
        }
        return LinearGradient(colors: colors.map { $0.opacity(0.85) }, startPoint: .top, endPoint: .bottom)
    }
}
