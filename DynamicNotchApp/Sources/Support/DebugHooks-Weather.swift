// DEBUG-only commands of the Weather widget (2026-10-20), registered with DebugCommandRegistry
// by DebugHooks.install (`WeatherDebug.install()`, also still called by `WeatherManager.start()`,
// only re-registers).
//   weatherlog              refresh now and log the place, age and first hourly slots ~3 s later
//   weatherpreview:<dir>    write <dir>/weather-<variant>.png: the widget offscreen at 200 × 202 pt
//                           (black background) — live (the manager's forecast), day / night-rain /
//                           snow / thunder samples, °F, hourly off, offline (3 h old + error),
//                           loading, error — and settings.png (Settings ▸ Widgets ▸ Weather, 520 pt).
//                           Samples are preview-only: nothing is fetched, cached or stored.
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum WeatherDebug {
    static func install() {
        DebugCommandRegistry.register("weatherlog", "refresh now and log the place, age and first hourly slots ~3 s later") { _ in
            WeatherManager.shared.refresh(force: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { log() }
        }
        DebugCommandRegistry.register("weatherpreview", usage: "weatherpreview:<dir>", "Weather widget live + samples (dark, 200 × 202) + settings.png") { arg in
            // These renders never forced the glass fallback; `?glass=` can.
            WidgetSnapshotter.session(arg, tag: "[Weather]", glass: .inherit) { preview(to: $0) }
        }
    }

    private static func log() {
        let m = WeatherManager.shared
        guard let f = m.forecast else {
            NSLog("[Weather] no forecast; error=%@", m.lastError ?? "-")
            return
        }
        NSLog("[Weather] %@ (%.3f, %.3f) current=%d fetched %.0fs ago, now %.1f°C code %d day=%d H %@ L %@ error=%@ access=%@",
              f.place.detail, f.place.latitude, f.place.longitude, f.isCurrentLocation ? 1 : 0,
              Date().timeIntervalSince(f.fetchedAt), f.current.temperature, f.current.code, f.current.isDay ? 1 : 0,
              f.high.map { String(format: "%.1f", $0) } ?? "-", f.low.map { String(format: "%.1f", $0) } ?? "-",
              m.lastError ?? "-", "\(m.locationAccess)")
        for h in f.strip() {
            NSLog("[Weather]   %@ %.1f°C code %d precip %@", WeatherWidgetView.hourLabel(h.time, in: f.timeZone),
                  h.temperature, h.code, h.precipitationProbability.map(String.init) ?? "-")
        }
    }

    static func sample(code: Int, isDay: Bool, temp: Double, place: WeatherPlace = .tokyo, ageHours: Double = 0,
                       hourCodes: [Int]? = nil, precip: [Int]? = nil) -> WeatherForecast {
        let now = Date()
        let start = Calendar.current.dateInterval(of: .hour, for: now)!.start
        let codes = hourCodes ?? Array(repeating: code, count: 24)
        let hours = (0..<24).map { i -> WeatherForecast.Hour in
            .init(time: start.addingTimeInterval(Double(i) * 3600), temperature: temp + sin(Double(i) / 4) * 3,
                  precipitationProbability: precip?[i % (precip?.count ?? 1)] ?? 0,
                  code: codes[i % codes.count], isDay: isDay)
        }
        return WeatherForecast(place: place, isCurrentLocation: false, fetchedAt: now.addingTimeInterval(-ageHours * 3600),
                               utcOffsetSeconds: TimeZone.current.secondsFromGMT(),
                               current: .init(time: now, temperature: temp, precipitationProbability: nil, code: code, isDay: isDay),
                               hourly: hours, high: temp + 4, low: temp - 6)
    }

    private static func preview(to dir: URL) {
        var c = WeatherWidgetSettings(); c.unit = .celsius
        var fahrenheit = c; fahrenheit.unit = .fahrenheit
        var noHourly = c; noHourly.showHourly = false
        let osaka = WeatherPlace(name: "Osaka", region: "Osaka", country: "Japan", latitude: 34.69, longitude: 135.50)
        let variants: [(String, WeatherWidgetView)] = [
            ("live", WeatherWidgetView()),
            ("day", WeatherWidgetView(previewForecast: .some(sample(code: 1, isDay: true, temp: 23, hourCodes: [1, 1, 2, 2, 3, 61], precip: [0, 0, 10, 20, 40, 70])), previewSettings: c)),
            ("night-rain", WeatherWidgetView(previewForecast: .some(sample(code: 63, isDay: false, temp: 14, place: osaka, hourCodes: [63, 61, 80, 3, 2, 0], precip: [90, 80, 60, 30, 10, 0])), previewSettings: c)),
            ("snow", WeatherWidgetView(previewForecast: .some(sample(code: 73, isDay: true, temp: -3, hourCodes: [73, 71, 77, 45, 3, 85], precip: [80])), previewSettings: c)),
            ("thunder-f", WeatherWidgetView(previewForecast: .some(sample(code: 95, isDay: true, temp: 29, hourCodes: [95, 96, 82, 81, 2, 0], precip: [70, 60, 50, 30, 0, 0])), previewSettings: fahrenheit)),
            ("hourly-off", WeatherWidgetView(previewForecast: .some(sample(code: 2, isDay: true, temp: 18)), previewSettings: noHourly)),
            ("offline", WeatherWidgetView(previewForecast: .some(sample(code: 45, isDay: true, temp: 11, ageHours: 3)), previewSettings: c,
                                          previewError: "The Internet connection appears to be offline.")),
            ("loading", WeatherWidgetView(previewForecast: .some(nil), previewSettings: c)),
            ("error", WeatherWidgetView(previewForecast: .some(nil), previewSettings: c, previewError: "The Internet connection appears to be offline.")),
        ]
        for dark in WidgetSnapshotter.appearances(default: [true]) {
            for (name, view) in variants {
                WidgetSnapshotter.write(view.frame(width: 200, height: 202)
                                            .background(dark ? Color.black : Color(nsColor: .windowBackgroundColor))
                                            .environment(\.colorScheme, dark ? .dark : .light),
                                        size: CGSize(width: 200, height: 202), dark: nil,
                                        to: dir.appendingPathComponent("weather-\(name)\(dark ? "" : "-light").png"), settle: 0.6)
            }
        }
        WidgetSnapshotter.write(WeatherWidgetSettingsView().frame(width: 520, height: 900),
                                size: CGSize(width: 520, height: 900), dark: nil,
                                to: dir.appendingPathComponent("settings.png"), settle: 0.6)
    }
}
#endif
