// Table-driven tests of the Calculator widget engine (Sources/CalculatorEngine.swift): arithmetic,
// percent, juxtaposition (the "3 h 20" → Missing operator rule), units, currency, bases, `ans`,
// time-zone queries and errors. Every case runs against one fixed context (rates, clock, locale,
// local zone), so results are deterministic on any machine.
import Foundation
import Testing
@testable import DynamicNotchApp   // the CLT harness library and the Xcode test-support library

/// USD-based rates of the tests (amount per 1 USD).
let calcTestRates = CalculatorRateTable(
    base: "USD", date: "2026-10-16",
    rates: ["EUR": 0.9, "JPY": 150, "GBP": 0.8, "CHF": 0.88, "KRW": 1350, "INR": 83, "CNY": 7.2],
    fetchedAt: Date(timeIntervalSince1970: 1_790_000_000))

/// Mon 2026-10-19 08:53:20 UTC (17:53 in Tokyo, 01:53 PDT).
let calcTestNow = Date(timeIntervalSince1970: 1_792_400_000)

func calcTestContext(ans: Double? = 21, rates: (any CalculatorRateProviding)? = calcTestRates) -> CalculatorContext {
    var c = CalculatorContext()
    c.rates = rates
    c.decimalDigits = 6
    c.defaultSourceCurrency = "USD"
    c.defaultTargetCurrency = "JPY"
    c.ans = ans
    c.now = calcTestNow
    c.locale = Locale(identifier: "en_GB")
    c.localTimeZone = TimeZone(identifier: "Asia/Tokyo")!
    return c
}

/// One expected outcome: the display (and optionally the detail line), an error, or nothing.
enum CalcExpect: CustomStringConvertible, Sendable {
    case shows(String)
    case showsWithDetail(String, String?)
    case fails(String)
    case empty

    var description: String {
        switch self {
        case .shows(let s): return "= \(s)"
        case .showsWithDetail(let s, let d): return "= \(s) | \(d ?? "-")"
        case .fails(let m): return "error \(m)"
        case .empty: return "empty"
        }
    }
}

struct CalcCase: CustomTestStringConvertible, Sendable {
    var input: String
    var expect: CalcExpect
    init(_ input: String, _ expect: CalcExpect) { self.input = input; self.expect = expect }
    var testDescription: String { "“\(input)” \(expect)" }
}

private func check(_ c: CalcCase, context: CalculatorContext = calcTestContext()) {
    let outcome = CalculatorEngine.evaluate(c.input, context: context)
    switch (c.expect, outcome) {
    case (.empty, .empty):
        break
    case (.shows(let display), .result(let r)):
        #expect(r.display == display, "“\(c.input)”")
    case (.showsWithDetail(let display, let detail), .result(let r)):
        #expect(r.display == display, "“\(c.input)”")
        #expect(r.detail == detail, "“\(c.input)”")
    case (.fails(let message), .error(let m)):
        #expect(m == message, "“\(c.input)”")
    default:
        Issue.record("“\(c.input)”: expected \(c.expect), got \(outcome)")
    }
}

@Suite("Calculator engine")
struct CalculatorEngineTests {

    // MARK: Arithmetic

    static let arithmetic: [CalcCase] = [
        .init("2+2", .shows("4")),
        .init("2+2=", .shows("4")),
        .init("   ", .empty),
        .init("1+2*3", .shows("7")),
        .init("(1+2)*3", .shows("9")),
        .init("2^3^2", .shows("512")),                 // right associative
        .init("-2^2", .shows("-4")),                   // -(2^2)
        .init("2^-1", .shows("0.5")),
        .init("2**10", .shows("1,024")),
        .init("10/4", .shows("2.5")),
        .init("7 × 6", .shows("42")),
        .init("9 ÷ 3", .shows("3")),
        .init("5 − 7", .shows("-2")),
        .init("10 mod 3", .shows("1")),
        .init("10 % 3", .shows("1")),                  // "%" before an operand is modulo
        .init("-5 % 3", .shows("1")),                  // floored
        .init("5!", .shows("120")),
        .init("0!", .shows("1")),
        .init("2.5!", .shows("3.323351")),             // Γ(3.5)
        .init("3!!", .shows("720")),
        .init("-3!", .shows("-6")),
        .init("1/3", .shows("0.333333")),
        .init("1e5", .shows("100,000")),
        .init("2.5E-3", .shows("0.0025")),
        .init("2e", .shows("5.436564")),               // 2 × e, not an exponent
        .init("0.0000001", .shows("1e-7")),
        .init("123456789012345678", .shows("1.234568e17")),
        .init("1,000 + 1", .shows("1,001")),
        .init("1,000,000 * 2", .shows("2,000,000")),
        .init("1_000_000", .shows("1,000,000")),
        .init("max(1,000)", .shows("1")),              // inside a call "," separates arguments
        .init("max(1, 5, 3)", .shows("5")),
        .init("min(4,2)", .shows("2")),
        .init("sqrt(16)", .shows("4")),
        .init("cbrt(27)", .shows("3")),
        .init("abs(-3)", .shows("3")),
        .init("log(1000)", .shows("3")),
        .init("ln(e)", .shows("1")),
        .init("log2(8)", .shows("3")),
        .init("exp(0)", .shows("1")),
        .init("floor(2.7)", .shows("2")),
        .init("ceil(2.1)", .shows("3")),
        .init("round(2.5)", .shows("3")),
        .init("trunc(-2.7)", .shows("-2")),
        .init("sign(-4)", .shows("-1")),
        .init("sin(30°)", .shows("0.5")),
        .init("sin(30 deg)", .shows("0.5")),
        .init("cos(pi)", .shows("-1")),
        .init("sin(pi)", .shows("0")),
        .init("tan(45°)", .shows("1")),
        .init("tau / 2", .shows("3.141593")),
    ]

    @Test(arguments: arithmetic)
    func arithmetic(_ c: CalcCase) { check(c) }

    // MARK: Percent

    static let percent: [CalcCase] = [
        .init("200 + 10%", .shows("220")),
        .init("200 - 10%", .shows("180")),
        .init("10%", .shows("0.1")),
        .init("15% of 80", .shows("12")),
        .init("10% * 50", .shows("5")),
        .init("10% + 5", .shows("5.1")),
        .init("5% + 5%", .shows("0.1")),               // stays a percentage (was 5.25)
        .init("20% - 5%", .shows("0.15")),
        .init("(10%)", .shows("0.1")),
        .init("200 + (10%)", .shows("200.1")),         // parenthesised: a plain 0.1
        .init("2 km + 50%", .shows("3 km")),
    ]

    @Test(arguments: percent)
    func percent(_ c: CalcCase) { check(c) }

    // MARK: Juxtaposition

    static let juxtaposition: [CalcCase] = [
        .init("2(3+1)", .shows("8")),
        .init("2pi", .shows("6.283185")),
        .init("2 pi", .shows("6.283185")),
        .init("(1+2)(3+4)", .shows("21")),
        .init("2 3", .fails("Missing operator")),
        .init("pi 2", .fails("Missing operator")),
        .init("3 h 20", .fails("Missing operator")),   // while typing "3 h 20 min": not 60 h
        .init("$5 3", .fails("Missing operator")),
        .init("2 km 3", .fails("Missing operator")),
        .init("3 h 20 min", .shows("3.333333 hr")),
        .init("3 h 20 min in min", .shows("200 min")),
        .init("5 ft 3 in", .shows("5.25 ft")),
        .init("5 ft 3 in in cm", .shows("160.02 cm")),
        .init("1 h 30 min 15 s in s", .shows("5,415 s")),
    ]

    @Test(arguments: juxtaposition)
    func juxtaposition(_ c: CalcCase) { check(c) }

    // MARK: Units

    static let units: [CalcCase] = [
        .init("12 km in mi", .shows("7.456454 mi")),
        .init("12 km to mi", .shows("7.456454 mi")),
        .init("12 km as mi", .shows("7.456454 mi")),
        .init("12 km -> mi", .shows("7.456454 mi")),
        .init("5 in in cm", .shows("12.7 cm")),       // the last valid keyword converts
        .init("km in mi", .shows("0.621371 mi")),      // a bare unit is one of it
        .init("100 °F in °C", .shows("37.777778°C")),
        .init("100 F in C", .shows("37.777778°C")),
        .init("0 C in F", .shows("32°F")),
        .init("37 celsius to fahrenheit", .shows("98.6°F")),
        .init("1 GB in MB", .shows("1,000 MB")),
        .init("1 GiB in MiB", .shows("1,024 MiB")),
        .init("500 mb in gb", .shows("0.5 GB")),       // lower-case spellings are bytes
        .init("8 Mb in MB", .shows("1 MB")),           // Mb = megabits
        .init("60 mph in km/h", .shows("96.560563 km/h")),
        .init("60 mph in km / h", .shows("96.560563 km/h")),
        .init("100 km/h in mph", .shows("62.137169 mph")),
        .init("1 m + 20 cm", .shows("1.2 m")),
        .init("1 m - 20 cm", .shows("0.8 m")),
        .init("1 m / 20 cm", .shows("5")),             // a ratio
        .init("2 kg * 3", .shows("6 kg")),
        .init("3 * 2 kg", .shows("6 kg")),
        .init("abs(-3 km)", .shows("3 km")),
        .init("1 fl oz in ml", .shows("29.5735 mL")),
        .init("2 cups in ml", .shows("480 mL")),
        .init("1 acre in m²", .shows("4,046.856422 m²")),
        .init("1000 m² in ha", .shows("0.1 ha")),
        .init("1 sq ft in m2", .shows("0.092903 m²")),        // was "Unknown word “sq”"
        .init("5 nautical miles in km", .shows("9.26 km")),   // was "Unknown word “nautical”"
        .init("1 light year in km", .shows("9,460,730,472,580.8 km")),
        .init("90 deg in rad", .shows("1.570796 rad")),
        .init("1 kWh in kJ", .shows("3,600 kJ")),
        .init("100 kcal in kJ", .shows("418.4 kJ")),
        .init("1 hp in W", .shows("745.7 W")),
        .init("2 weeks in days", .shows("14 d")),
        .init("1 year in days", .shows("365.25 d")),
        .init("90 min in h", .shows("1.5 hr")),
        .init("1 h in s", .shows("3,600 s")),
        // custom units against Foundation's (was "Can't combine time and time" etc.)
        .init("1 day in h", .shows("24 hr")),
        .init("1 day + 12 h", .shows("1.5 d")),
        .init("1 atm in psi", .shows("14.695943 psi")),
        .init("1 turn in deg", .shows("360°")),
        .init("60 rpm in hz", .shows("1 Hz")),
        .init("1 m * 1 m", .fails("Can't multiply two quantities")),
        .init("1 m + 1 kg", .fails("Can't combine length and mass")),
        .init("1 h in km", .fails("Can't combine time and length")),
        .init("5 + 1 m", .fails("Can't add a number and m")),
        .init("1 m + 5", .fails("Can't add a number and m")),
        .init("5 in km/h", .fails("Add a unit to convert to km/h")),
        .init("2 m ^ 2", .fails("Can't raise a quantity to a power")),
        .init("1 m / 0 cm", .fails("Division by zero")),
    ]

    @Test(arguments: units)
    func units(_ c: CalcCase) { check(c) }

    // MARK: Currency

    static let currency: [CalcCase] = [
        .init("100 usd", .showsWithDetail("15,000 JPY", "1 USD = 150 JPY · 2026-10-16")),
        .init("100 usd in eur", .showsWithDetail("90.00 EUR", "1 USD = 0.9 EUR · 2026-10-16")),
        .init("$100 in eur", .shows("90.00 EUR")),
        .init("€50 in usd", .showsWithDetail("55.56 USD", "1 EUR = 1.111111 USD · 2026-10-16")),
        .init("100 jpy", .shows("0.67 USD")),          // already in the target → the source currency
        .init("100 usd + 10 eur", .shows("16,667 JPY")),
        .init("$100 + 10%", .shows("16,500 JPY")),
        .init("5 dollars", .shows("750 JPY")),
        .init("5 dollars in yen", .shows("750 JPY")),
        .init("€5", .shows("833 JPY")),
        .init("£10 in $", .shows("12.50 USD")),
        .init("$ 5", .shows("750 JPY")),
        .init("$5 €3", .shows("1,250 JPY")),           // juxtaposed amounts add
        .init("100 usd / 2", .shows("7,500 JPY")),
        .init("100 usd / 50 usd", .shows("2")),
        .init("100 usd / 50 eur", .shows("1.8")),
        .init("100 usd * 100 usd", .fails("Can't multiply two quantities")),
        .init("100 usd in km", .fails("Can't convert money to km")),
        .init("5 km in usd", .fails("Can't convert km to money")),
        .init("100 usd + 5", .fails("Can't add a number and USD")),
        .init("100 usd in xyz", .fails("Unknown word “in”")),
        .init("$", .fails("Expected an amount after the currency sign")),
        .init("5 in usd", .fails("Add a currency to convert to USD")),
        .init("100 aud in usd", .fails("No rate for AUD → USD")),   // known code, no rate in the table
    ]

    @Test(arguments: currency)
    func currency(_ c: CalcCase) { check(c) }

    @Test func currencyResultsAreFlagged() throws {
        guard case .result(let r) = CalculatorEngine.evaluate("100 usd in eur", context: calcTestContext()) else {
            Issue.record("no result"); return
        }
        #expect(r.usesCurrency)
        #expect(r.number == 90)
        guard case .result(let plain) = CalculatorEngine.evaluate("100 usd / 50 usd", context: calcTestContext()) else {
            Issue.record("no result"); return
        }
        #expect(!plain.usesCurrency)
    }

    @Test func offlineCurrency() {
        let offline = calcTestContext(rates: nil)
        check(.init("100 usd", .fails("Exchange rates unavailable (offline)")), context: offline)
        check(.init("100 usd + 5 eur", .fails("Exchange rates unavailable (offline)")), context: offline)
        // same-currency arithmetic needs no rates
        var sameCurrency = offline
        sameCurrency.defaultTargetCurrency = "USD"
        sameCurrency.defaultSourceCurrency = "USD"
        check(.init("$5 + $3", .shows("8.00 USD")), context: sameCurrency)
    }

    /// The engine converts with whatever provider it is given (injection, not the app's table).
    @Test func customRateProvider() {
        struct Fixed: CalculatorRateProviding {
            func rate(from: String, to: String) -> Double? { from == to ? 1 : 2 }
            var codes: Set<String> { ["XAU"] }
            var date: String { "fixed" }
        }
        var c = calcTestContext(rates: Fixed())
        c.defaultTargetCurrency = "EUR"
        check(.init("3 usd", .showsWithDetail("6.00 EUR", "1 USD = 2 EUR · fixed")), context: c)
        check(.init("1 xau in usd", .shows("2.00 USD")), context: c)   // a code only the provider knows
    }

    @Test func rateTable() {
        #expect(calcTestRates.rate(from: "USD", to: "JPY") == 150)
        #expect(calcTestRates.rate(from: "JPY", to: "USD") == 1.0 / 150)
        #expect(calcTestRates.rate(from: "EUR", to: "GBP")! - 0.8 / 0.9 < 1e-12)
        #expect(calcTestRates.rate(from: "USD", to: "XYZ") == nil)
        #expect(calcTestRates.codes.contains("USD"))
    }

    // MARK: Bases

    static let bases: [CalcCase] = [
        .init("0xFF", .showsWithDetail("255", "= 0xFF")),
        .init("0xff + 1", .showsWithDetail("256", "= 0x100")),
        .init("0b1111 + 1", .showsWithDetail("16", "= 0b1 0000")),
        .init("0o17", .showsWithDetail("15", "= 0o17")),
        .init("255 in hex", .showsWithDetail("0xFF", "= 255")),
        .init("255 to bin", .showsWithDetail("0b1111 1111", "= 255")),
        .init("10 in bin", .shows("0b1010")),
        .init("-255 in hex", .shows("-0xFF")),
        .init("0xFF in dec", .showsWithDetail("255", nil)),
        .init("15 in hex", .shows("0xF")),                    // not a time
        .init("1.5 in hex", .fails("Base conversion needs a whole number")),
    ]

    @Test(arguments: bases)
    func bases(_ c: CalcCase) { check(c) }

    // MARK: ans

    static let ans: [CalcCase] = [
        .init("ans", .shows("21")),
        .init("ans * 2", .shows("42")),
        .init("ans + 1", .shows("22")),
        .init("2 ans", .shows("42")),
        .init("ANS / 3", .shows("7")),
    ]

    @Test(arguments: ans)
    func ans(_ c: CalcCase) { check(c) }

    @Test func ansWithoutPreviousResult() {
        check(.init("ans + 1", .fails("No previous result")), context: calcTestContext(ans: nil))
    }

    @Test(arguments: [
        ("ans * 2", true), ("2 + ANS", true), ("answer", false), ("ans2", false), ("2 + 2", false), ("(ans)", true),
    ])
    func referencesAns(_ input: String, _ expected: Bool) {
        #expect(CalculatorEngine.referencesAns(input) == expected)
    }

    @Test(arguments: [
        ("100 usd", true), ("$5", true), ("€", true), ("2 + 2", false), ("12 km", false), ("eu", false), ("100 eur", true),
    ])
    func mayNeedRates(_ input: String, _ expected: Bool) {
        #expect(CalculatorEngine.mayNeedRates(input) == expected)
    }

    // MARK: Time zones (dates)

    static let time: [CalcCase] = [
        .init("15:00 JST in PST", .showsWithDetail("23:00 PDT (previous day)", "Mon 15:00 Tokyo → America/Los_Angeles")),
        .init("15:00 in PST", .shows("23:00 PDT (previous day)")),   // source = the local zone (Tokyo)
        .init("3pm EST to Tokyo", .showsWithDetail("04:00 Tokyo (next day)", "Mon 15:00 EDT → Asia/Tokyo")),
        .init("3pm in Tokyo", .shows("15:00 Tokyo")),
        .init("9:30am in UTC+9", .shows("09:30 UTC+9")),
        .init("9:30 am in UTC+5:30", .shows("06:00 UTC+5:30")),
        .init("12am in UTC", .shows("15:00 UTC (previous day)")),
        .init("12pm in UTC", .shows("03:00 UTC")),
        .init("now in UTC", .shows("08:53 UTC")),
        .init("now in tokyo", .shows("17:53 Tokyo")),
        .init("time in PST", .shows("01:53 PDT")),
        .init("23:00 JST in PST", .shows("07:00 PDT")),
        .init("15:00 local in UTC", .shows("06:00 UTC")),
        .init("10:00 UTC in new york", .shows("06:00 EDT")),
        .init("10:00 UTC in nyc", .shows("06:00 EDT")),
        .init("10:00 UTC in Europe/Paris", .shows("12:00 Paris")),
        .init("10:00 UTC to GMT-3", .shows("07:00 UTC-3")),
        .init("10:00 UTC -> CET", .shows("12:00 Paris")),
        .init("15:00 in cm", .fails("Unknown time zone “cm”")),
        .init("3pm in cm", .fails("Unknown time zone “cm”")),       // was "Unknown word “pm”"
        .init("15:00 xyz in UTC", .fails("Unknown time zone “xyz”")),
        .init("13pm in UTC", .fails("Invalid time")),
        .init("25:00 in UTC", .fails("Invalid time")),
        .init("10:61 in UTC", .fails("Invalid time")),
    ]

    @Test(arguments: time)
    func time(_ c: CalcCase) { check(c) }

    /// "local" / "here" are the context's zone, not the machine's.
    @Test func localZoneIsInjected() {
        var c = calcTestContext()
        c.localTimeZone = TimeZone(identifier: "Europe/London")!
        check(.init("12:00 here in UTC", .shows("11:00 UTC")), context: c)   // BST in October
        check(.init("12:00 in UTC", .shows("11:00 UTC")), context: c)
        #expect(CalcTimeQuery.zone("local", local: TimeZone(identifier: "Asia/Seoul")!)?.identifier == "Asia/Seoul")
    }

    @Test(arguments: [
        ("JST", "Asia/Tokyo"), ("pst", "America/Los_Angeles"), ("UTC", "GMT"), ("Z", "GMT"),
        ("tokyo", "Asia/Tokyo"), ("new york", "America/New_York"), ("sf", "America/Los_Angeles"),
        ("Europe/Berlin", "Europe/Berlin"),
    ])
    func zoneNames(_ name: String, _ identifier: String) {
        #expect(CalcTimeQuery.zone(name)?.identifier == identifier)
    }

    @Test func zoneOffsets() {
        #expect(CalcTimeQuery.zone("UTC+9")?.secondsFromGMT() == 9 * 3600)
        #expect(CalcTimeQuery.zone("GMT-5:30")?.secondsFromGMT() == -(5 * 3600 + 30 * 60))
        #expect(CalcTimeQuery.zone("UTC+0530")?.secondsFromGMT() == 5 * 3600 + 30 * 60)
        #expect(CalcTimeQuery.zone("UTC+15") == nil)
        #expect(CalcTimeQuery.zone("narnia") == nil)
    }

    // MARK: Errors

    static let errors: [CalcCase] = [
        .init("1/0", .fails("Division by zero")),
        .init("0/0", .fails("Division by zero")),
        .init("10 mod 0", .fails("Division by zero")),
        .init("10^400", .fails("Result is too large")),
        .init("1e300 km * 1e300", .fails("Result is too large")),   // quantities too (was "inf km")
        .init("sqrt 16", .fails("sqrt needs parentheses: sqrt(…)")),
        .init("sqrt(-1)", .fails("Not a real number")),
        .init("max()", .fails("max needs at least one value")),
        .init("sqrt(1, 2)", .fails("sqrt takes one value")),
        .init("(-3)!", .fails("Factorial of a negative number")),
        .init("2 +", .fails("Incomplete expression")),
        .init("(2+3", .fails("Missing “)”")),
        .init("2)", .fails("Unexpected “)”")),
        .init("foo", .fails("Unknown word “foo”")),
        .init("#", .fails("Unexpected “#”")),
        .init(", ", .fails("Unexpected “,”")),
        .init("1,0000", .fails("Unexpected “,”")),     // not a thousands separator
        .init("1.5,000", .fails("Unexpected “,”")),
        .init("5 to", .fails("Unknown word “to”")),
        .init("0xFFFFFFFFFFFFFFFFF", .fails("Invalid number 0xFFFFFFFFFFFFFFFFF")),
    ]

    @Test(arguments: errors)
    func errors(_ c: CalcCase) { check(c) }

    // MARK: Formatting

    @Test func decimalDigitsSetting() {
        var c = calcTestContext()
        c.decimalDigits = 2
        check(.init("1/3", .shows("0.33")), context: c)
        check(.init("100 eur in usd", .shows("111.11 USD")), context: c)
        c.decimalDigits = 0
        check(.init("100 eur in usd", .shows("111 USD")), context: c)   // capped by the setting
    }

    @Test func localeIsInjected() {
        var c = calcTestContext()
        c.locale = Locale(identifier: "de_DE")
        check(.init("1234.5 * 2", .shows("2.469")), context: c)
        check(.init("1/4", .shows("0,25")), context: c)
    }

    @Test func formatter() {
        let f = CalculatorFormatter(digits: 6, locale: Locale(identifier: "en_GB"))
        #expect(f.based(255, base: 16) == "0xFF")
        #expect(f.based(10, base: 2) == "0b1010")
        #expect(f.based(1.5, base: 16) == nil)
        #expect(f.money(1234.6, "JPY") == "1,235 JPY")
        #expect(f.money(1234.5, "JPY") == "1,234 JPY")   // half-even, like the number formatter
        #expect(f.money(1234.5, "EUR") == "1,234.50 EUR")
        #expect(CalculatorFormatter.currencyFractionDigits("KRW") == 0)
        #expect(CalculatorFormatter.currencyFractionDigits("USD") == 2)
    }

    @Test func unitPhrases() throws {
        let tokens = try CalcLexer.tokenize("km / h fl oz m ² sq ft kg")
        #expect(CalcUnits.phrase(tokens, at: 0)?.consumed == 3)
        #expect(CalcUnits.phrase(tokens, at: 3)?.unit == UnitVolume.fluidOunces)
        #expect(CalcUnits.phrase(tokens, at: 5)?.unit == UnitArea.squareMeters)
        #expect(CalcUnits.phrase(tokens, at: 7)?.unit == UnitArea.squareFeet)
        #expect(CalcUnits.phrase(tokens, at: 9)?.consumed == 1)
        #expect(CalcUnits.sameDimension(CalcUnits.day, UnitDuration.hours))
        #expect(!CalcUnits.sameDimension(CalcUnits.day, UnitLength.meters))
    }

    @Test func lexer() throws {
        #expect(try CalcLexer.tokenize("1,000.5+0x1F") == [.number(1000.5, base: 10), .op("+"), .number(31, base: 16)])
        #expect(try CalcLexer.tokenize("max(1,000)") == [.ident("max"), .op("("), .number(1, base: 10), .op(","), .number(0, base: 10), .op(")")])
        #expect(try CalcLexer.tokenize("5 => km") == [.number(5, base: 10), .op("->"), .ident("km")])
        #expect(try CalcLexer.tokenize("€3 °C") == [.currencySymbol("EUR"), .number(3, base: 10), .ident("°C")])
    }
}
