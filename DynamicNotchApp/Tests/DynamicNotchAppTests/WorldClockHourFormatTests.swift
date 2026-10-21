// WorldClockWidgetSettings.usesTwelveHourClock and its tolerant decoding.
import Foundation
import Testing
@testable import DynamicNotchApp

@Suite("World clock hour format")
struct WorldClockHourFormatTests {
    @Test("Explicit formats override the locale")
    func explicit() {
        var s = WorldClockWidgetSettings()
        s.hourFormat = .twelveHour
        #expect(s.usesTwelveHourClock)
        s.hourFormat = .twentyFourHour
        #expect(!s.usesTwelveHourClock)
    }

    @Test("System format follows the current locale's \"j\" pattern")
    func system() {
        var s = WorldClockWidgetSettings()
        s.hourFormat = .system
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? "HH"
        let symbols = pattern.replacingOccurrences(of: "'[^']*'", with: "", options: .regularExpression)
        #expect(s.usesTwelveHourClock == symbols.contains(where: { "ahK".contains($0) }))
    }

    @Test("Missing or unknown keys decode to defaults")
    func tolerantDecoding() throws {
        let decoded = try JSONDecoder().decode(WorldClockWidgetSettings.self, from: Data(#"{"hourFormat":"bogus"}"#.utf8))
        #expect(decoded.hourFormat == .system)
        #expect(decoded.showSeconds == false)
        #expect(!decoded.clocks.isEmpty)
        let roundTrip = try JSONDecoder().decode(WorldClockWidgetSettings.self,
                                                 from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }
}
