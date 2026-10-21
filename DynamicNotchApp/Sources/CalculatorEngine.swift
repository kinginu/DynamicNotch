// Calculator widget engine (2026-10-20). Pure Foundation, no UI, no NSExpression: user input
// is tokenized and evaluated by a small recursive-descent parser, so nothing the user types is
// ever executed or passed to a format/selector API. Deterministic for a given `CalculatorContext`
// (clock `now`, `locale`, `localTimeZone` and the exchange-rate provider are all injected).
// Tests: Tests/EngineTests/CalculatorEngineTests.swift.
//
// Grammar (case-insensitive keywords; whitespace is free):
//
//   input      := timeQuery | expr [ convKw target ]
//   convKw     := "in" | "to" | "as" | "into" | "->" | "=>"  (the LAST top-level one whose right
//                                                            side is a valid target wins, so
//                                                            "5 in in cm" works)
//   target     := unitPhrase | currency | "hex" | "bin" | "oct" | "dec"
//   expr       := term { ("+" | "-") term }                 (a ± b% = a × (1 ± b/100))
//   term       := power { ("*" | "×" | "·" | "/" | "÷" | "mod" | "%" ) power | "of" power
//                       | juxtaposed power }                (2(3+1) and 2pi multiply;
//                                                            "3 h 20 min" / "5 ft 3 in" add)
//   power      := unary [ ("^" | "**") power ]               (right associative; -2^2 = -4)
//   unary      := ("-" | "+" | "−") unary | postfix
//   postfix    := primary { "%" | "!" | unitPhrase | currency }
//   primary    := number | currencySymbol number | "(" expr ")" | func "(" expr { "," expr } ")"
//               | constant | "ans" | unitPhrase | currency   (a bare unit / currency is one of it)
//   unitPhrase := unit | unit "/" unit ("km / h") | unit "²"|"³" | ("fl"|"sq"|"nautical"|"light") word
//                                                           ("fl oz", "sq ft", "nautical miles")
//   number     := decimal [exponent] | "0x"hex | "0b"bin | "0o"oct   ("_" and "," separators
//                                                                   inside decimals are allowed:
//                                                                   1,000.5 / 1_000)
//   func       := sqrt cbrt abs ln log log2 log10 exp sin cos tan asin acos atan sinh cosh tanh
//                 floor ceil round trunc sign min max     (trig takes radians, or degrees with
//                                                          a unit: sin(30°), sin(30 deg))
//   constant   := pi π tau τ e
//   timeQuery  := (HH[:MM] [am|pm] | "now" | "time") [zone] ("in"|"to"|"->") zone
//   zone       := abbreviation (JST, PST, CET, UTC…) | UTC±H[:MM] | IANA id | city (tokyo, new york)
//               | "local" | "here"                         (= `CalculatorContext.localTimeZone`)
//
// Semantics:
// - Percent: a trailing "%" marks a percentage. `a + b%` / `a - b%` scale a by (1 ± b/100);
//   `b% of a` is a × b/100; `b% + c%` stays a percentage; anywhere else b% is b/100 (`10% * 50` = 5).
//   A "%" followed by an operand is modulo (`10 % 3` = 1, floored for numbers).
// - Juxtaposition: two quantities of the same kind add (`3 h 20 min`, `5 ft 3 in`, `$5 €3`);
//   a number, constant, `ans` or parenthesis after an operand multiplies (`2pi`, `2(3+1)`, `2 ans`);
//   but a bare NUMBER after any operand is "Missing operator" (`2 3`, `$5 3`, `3 h 20` — so the line
//   does not briefly show 60 h while "3 h 20 min" is being typed).
// - Units: Foundation `Dimension`s; + and - convert the right side to the left side's unit; / of
//   two quantities of the same kind is a plain ratio; × of two quantities is rejected. Units of
//   different kinds never combine. Temperatures convert affinely (10 °C + 5 °F = -5 °C).
// - Currency: amounts are `.money`; + / - / ratio convert through the rate provider (rates are
//   "amount of X per 1 base"). A bare amount converts to `defaultTargetCurrency`, or to
//   `defaultSourceCurrency` when it already is in the target currency. Without rates, any
//   cross-currency step is the error "Exchange rates unavailable (offline)".
// - `ans`: the previous result's number (`CalculatorContext.ans`); "No previous result" without one.
// - Time queries: the time is today's date (`now`) in the source zone (default `localTimeZone`);
//   the result shows "(next day)" / "(previous day)" when the target's date differs. A bare number
//   ("15 in hex") is never a time: hh:mm, am/pm, "now" or "time" is required.
//
// Units: Foundation `Dimension` subclasses (length, mass, duration, temperature, information,
// speed, area, volume, energy, power, pressure, angle, frequency) plus a few custom
// `UnitConverterLinear` units (day, week, year, atm, turn, rpm). Currencies: ISO codes, symbols
// ($ € £ ¥ ₩ ₹) and a few words (dollar, euro, yen…), converted with a `CalculatorRateProviding`
// (in the app `CalculatorRateTable`, Frankfurter / ECB).
import Foundation

// MARK: - Public API

/// One evaluation of the input line.
enum CalculatorOutcome: Equatable {
    /// Nothing to show (empty input).
    case empty
    /// A result: `display` is shown in the widget and copied; `detail` is a secondary line
    /// (e.g. "= 0xFF", rate date).
    case result(CalculatorResult)
    /// The input cannot be evaluated; `message` is shown inline.
    case error(String)
}

struct CalculatorResult: Equatable {
    var display: String
    var detail: String?
    /// The numeric value (for `ans`), when the result is a plain number or quantity.
    var number: Double?
    /// The result needs exchange rates (the view refreshes them).
    var usesCurrency = false
}

/// Exchange rates the engine converts with (injectable; the app passes `CalculatorRateTable`).
protocol CalculatorRateProviding {
    /// Amount of `to` for 1 `from`, nil if either code is unknown.
    func rate(from: String, to: String) -> Double?
    /// ISO codes the provider knows (beyond `CalculatorEngine.knownCurrencies`).
    var codes: Set<String> { get }
    /// Date of the rates, shown in the result's detail line ("2026-10-16").
    var date: String { get }
}

/// Exchange rates relative to one base currency (amount of currency X per 1 base).
struct CalculatorRateTable: Equatable, Codable, CalculatorRateProviding {
    var base: String
    var date: String
    var rates: [String: Double]
    var fetchedAt: Date

    /// Amount of `to` for 1 `from`, nil if either code is unknown.
    func rate(from: String, to: String) -> Double? {
        func perBase(_ c: String) -> Double? { c == base ? 1 : rates[c] }
        guard let f = perBase(from), let t = perBase(to), f > 0 else { return nil }
        return t / f
    }

    var codes: Set<String> { Set(rates.keys).union([base]) }
}

struct CalculatorContext {
    var rates: (any CalculatorRateProviding)?
    /// Maximum fraction digits of results.
    var decimalDigits: Int = 6
    /// Currency a bare currency amount ("100 usd") is converted to; if the amount is already in it,
    /// `defaultSourceCurrency` is used instead.
    var defaultTargetCurrency: String = "JPY"
    var defaultSourceCurrency: String = "USD"
    /// Previous result (`ans`).
    var ans: Double?
    /// Clock of time queries ("now in UTC", and today's date of "15:00 JST in PST").
    var now: Date = Date()
    var locale: Locale = .current
    /// Zone of a time without a source zone ("15:00 in PST"), and of "local" / "here".
    var localTimeZone: TimeZone = .current
}

enum CalculatorEngine {
    static func evaluate(_ input: String, context: CalculatorContext) -> CalculatorOutcome {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        if let time = CalcTimeQuery.evaluate(text, context: context) { return time }
        do {
            let tokens = try CalcLexer.tokenize(text)
            guard !tokens.isEmpty else { return .empty }
            var evaluator = CalcEvaluator(context: context)
            return try evaluator.run(tokens)
        } catch let error as CalcError {
            return .error(error.message)
        } catch {
            return .error(String(localized: "Can't evaluate"))
        }
    }

    /// Whether `input` uses `ans` as a word (so committing its result changes what it evaluates to).
    /// "answer" and "ans2" do not count.
    static func referencesAns(_ input: String) -> Bool {
        guard let tokens = try? CalcLexer.tokenize(input) else {
            return input.range(of: #"(?<![A-Za-z_])ans(?![A-Za-z0-9_])"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return tokens.contains { if case .ident(let w) = $0 { return w.lowercased() == "ans" } else { return false } }
    }

    /// Whether `input` may need exchange rates: a currency sign, or a word of three or more letters
    /// (it is, or could still become while typing, a currency code or word). Cheap; lets the view
    /// refresh the rates before the result needs them.
    static func mayNeedRates(_ input: String) -> Bool {
        guard let tokens = try? CalcLexer.tokenize(input) else { return false }
        return tokens.contains { token in
            switch token {
            case .currencySymbol: return true
            case .ident(let w): return w.count >= 3 && w.allSatisfy(\.isLetter)
            default: return false
            }
        }
    }

    /// Currency codes known without network (Frankfurter's list).
    static let knownCurrencies: [String] = [
        "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS",
        "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB",
        "TRY", "USD", "ZAR",
    ]
}

struct CalcError: Error, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
}

// MARK: - Lexer

enum CalcToken: Equatable {
    case number(Double, base: Int)      // base 10 / 16 / 2 / 8 (literal form)
    case ident(String)                  // words, unit symbols, currency codes
    case op(String)                     // + - * / ^ % ! ( ) , and the conversion arrow "->"
    case currencySymbol(String)         // ISO code of $ € £ ¥ ₩ ₹
}

enum CalcLexer {
    static let symbolCurrencies: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₩": "KRW", "₹": "INR"]

    static func tokenize(_ s: String) throws -> [CalcToken] {
        var tokens: [CalcToken] = []
        let chars = Array(s)
        var i = 0
        func peek(_ k: Int = 0) -> Character? { i + k < chars.count ? chars[i + k] : nil }
        func isDigit(_ k: Int) -> Bool { k < chars.count && chars[k].isASCII && chars[k].isNumber }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            // base literals
            if c == "0", let n = peek(1), "xXbBoO".contains(n) {
                let base = "xX".contains(n) ? 16 : "bB".contains(n) ? 2 : 8
                var j = i + 2, digits = ""
                while j < chars.count, chars[j].isHexDigit || chars[j] == "_" {
                    if chars[j] != "_" { digits.append(chars[j]) }
                    j += 1
                }
                if !digits.isEmpty {
                    guard let v = UInt64(digits, radix: base) else {
                        throw CalcError(String(localized: "Invalid number \(String(chars[i..<j]))"))
                    }
                    tokens.append(.number(Double(v), base: base))
                    i = j
                    continue
                }
            }
            if isDigit(i) || (c == "." && isDigit(i + 1)) {
                var j = i, text = ""
                var seenDot = false
                while j < chars.count {
                    let d = chars[j]
                    if isDigit(j) { text.append(d); j += 1 }
                    else if d == "." && !seenDot && isDigit(j + 1) { seenDot = true; text.append(d); j += 1 }
                    else if d == "_" && isDigit(j + 1) { j += 1 }
                    // thousands separator "1,000": exactly three digits follow, before the decimal
                    // point and not inside a call (where "," separates arguments: max(1,000) is
                    // two arguments)
                    else if d == ",", !seenDot, (1...3).allSatisfy({ isDigit(j + $0) }), !isDigit(j + 4),
                            !insideCall(tokens) { j += 1 }
                    else { break }
                }
                // exponent: 1e5, 2.5E-3 (not "2 e" the constant: needs a digit right after)
                if j < chars.count, "eE".contains(chars[j]) {
                    var k = j + 1
                    if k < chars.count, "+-".contains(chars[k]) { k += 1 }
                    if isDigit(k) {
                        text.append("e")
                        if "+-".contains(chars[j + 1]) { text.append(chars[j + 1]) }
                        while isDigit(k) { text.append(chars[k]); k += 1 }
                        j = k
                    }
                }
                guard let v = Double(text) else { throw CalcError(String(localized: "Invalid number \(text)")) }
                tokens.append(.number(v, base: 10))
                i = j
                continue
            }
            if let code = symbolCurrencies[c] { tokens.append(.currencySymbol(code)); i += 1; continue }
            if (c == "-" || c == "=") && peek(1) == ">" { tokens.append(.op("->")); i += 2; continue }
            if c == "*" && peek(1) == "*" { tokens.append(.op("^")); i += 2; continue }
            switch c {
            case "+", "-", "*", "/", "^", "%", "!", "(", ")", ",":
                tokens.append(.op(String(c))); i += 1; continue
            case "×", "·", "⋅": tokens.append(.op("*")); i += 1; continue
            case "÷": tokens.append(.op("/")); i += 1; continue
            case "−", "–": tokens.append(.op("-")); i += 1; continue
            case "=": i += 1; continue   // trailing "=" ("2+2=") is ignored
            case "°":
                // °C / °F / ° (degrees of angle)
                if let n = peek(1), "CcFf".contains(n), !(peek(2)?.isLetter ?? false) {
                    tokens.append(.ident("°" + String(n).uppercased())); i += 2
                } else {
                    tokens.append(.ident("°")); i += 1
                }
                continue
            case "²", "³":
                tokens.append(.ident(String(c))); i += 1; continue
            default: break
            }
            if c.isLetter || c == "µ" || c == "π" || c == "τ" {
                var j = i, word = ""
                while j < chars.count, chars[j].isLetter || chars[j] == "µ" || (isDigit(j) && !word.isEmpty) || chars[j] == "²" || chars[j] == "³" {
                    word.append(chars[j]); j += 1
                }
                tokens.append(.ident(word))
                i = j
                continue
            }
            throw CalcError(String(localized: "Unexpected “\(String(c))”"))
        }
        return tokens
    }

    /// Whether the token list ends inside an unclosed function call / parenthesis (a "," there
    /// separates arguments).
    private static func insideCall(_ tokens: [CalcToken]) -> Bool {
        var depth = 0
        for t in tokens {
            if t == .op("(") { depth += 1 } else if t == .op(")") { depth -= 1 }
        }
        return depth > 0
    }
}

// MARK: - Values

enum CalcValue {
    case number(Double)
    case measure(Double, Dimension)
    case money(Double, String)

    var isPlain: Bool { if case .number = self { return true } else { return false } }

    /// The magnitude, whatever the unit.
    var magnitude: Double {
        switch self {
        case .number(let n), .measure(let n, _), .money(let n, _): return n
        }
    }
}

/// A parsed operand: the value plus calculator flags.
struct CalcOperand {
    var value: CalcValue
    /// Written with a trailing "%" (a ± b% means a × (1 ± b/100)).
    var isPercent = false
}

// MARK: - Units

enum CalcUnits {
    static let day = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    static let week = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
    static let year = UnitDuration(symbol: "yr", converter: UnitConverterLinear(coefficient: 31_557_600))
    static let atm = UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101_325))
    static let turn = UnitAngle(symbol: "turn", converter: UnitConverterLinear(coefficient: 360))
    static let rpm = UnitFrequency(symbol: "rpm", converter: UnitConverterLinear(coefficient: 1.0 / 60))

    /// Exact-case aliases (checked first): symbols whose case matters (MB vs Mb, mL vs ML…).
    static let exact: [String: Dimension] = [
        // information: bytes upper-case B, bits lower-case b
        "B": UnitInformationStorage.bytes, "kB": UnitInformationStorage.kilobytes, "KB": UnitInformationStorage.kilobytes,
        "MB": UnitInformationStorage.megabytes, "GB": UnitInformationStorage.gigabytes, "TB": UnitInformationStorage.terabytes,
        "PB": UnitInformationStorage.petabytes,
        "KiB": UnitInformationStorage.kibibytes, "MiB": UnitInformationStorage.mebibytes, "GiB": UnitInformationStorage.gibibytes,
        "TiB": UnitInformationStorage.tebibytes,
        "b": UnitInformationStorage.bits, "Kb": UnitInformationStorage.kilobits,
        "Mb": UnitInformationStorage.megabits, "Gb": UnitInformationStorage.gigabits, "Tb": UnitInformationStorage.terabits,
        // temperature / energy / pressure symbols
        "C": UnitTemperature.celsius, "F": UnitTemperature.fahrenheit, "K": UnitTemperature.kelvin,
        "J": UnitEnergy.joules, "kJ": UnitEnergy.kilojoules, "kWh": UnitEnergy.kilowattHours,
        "W": UnitPower.watts, "kW": UnitPower.kilowatts, "MW": UnitPower.megawatts, "GW": UnitPower.gigawatts, "mW": UnitPower.milliwatts,
        "Pa": UnitPressure.newtonsPerMetersSquared, "hPa": UnitPressure.hectopascals, "kPa": UnitPressure.kilopascals,
        "MPa": UnitPressure.megapascals,
        "Hz": UnitFrequency.hertz, "kHz": UnitFrequency.kilohertz, "MHz": UnitFrequency.megahertz, "GHz": UnitFrequency.gigahertz,
        "L": UnitVolume.liters, "mL": UnitVolume.milliliters,
    ]

    /// Case-insensitive aliases (keys lower-case).
    static let loose: [String: Dimension] = {
        var t: [String: Dimension] = [:]
        func add(_ names: [String], _ unit: Dimension) { for n in names { t[n.lowercased()] = unit } }
        // length
        add(["m", "meter", "meters", "metre", "metres"], UnitLength.meters)
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], UnitLength.kilometers)
        add(["cm", "centimeter", "centimeters", "centimetre", "centimetres"], UnitLength.centimeters)
        add(["mm", "millimeter", "millimeters", "millimetre", "millimetres"], UnitLength.millimeters)
        add(["µm", "um", "micrometer", "micrometers", "micron", "microns"], UnitLength.micrometers)
        add(["nm", "nanometer", "nanometers"], UnitLength.nanometers)
        add(["mi", "mile", "miles"], UnitLength.miles)
        add(["yd", "yard", "yards"], UnitLength.yards)
        add(["ft", "foot", "feet"], UnitLength.feet)
        add(["in", "inch", "inches"], UnitLength.inches)
        add(["nmi", "nauticalmile", "nauticalmiles"], UnitLength.nauticalMiles)
        add(["ly", "lightyear", "lightyears"], UnitLength.lightyears)
        add(["au"], UnitLength.astronomicalUnits)
        // mass
        add(["kg", "kilogram", "kilograms", "kilo", "kilos"], UnitMass.kilograms)
        add(["g", "gram", "grams", "gramme", "grammes"], UnitMass.grams)
        add(["mg", "milligram", "milligrams"], UnitMass.milligrams)
        add(["µg", "ug", "microgram", "micrograms"], UnitMass.micrograms)
        add(["lb", "lbs", "pound", "pounds"], UnitMass.pounds)
        add(["oz", "ounce", "ounces"], UnitMass.ounces)
        add(["t", "tonne", "tonnes", "ton", "tons"], UnitMass.metricTons)
        add(["st", "stone", "stones"], UnitMass.stones)
        add(["ct", "carat", "carats"], UnitMass.carats)
        // duration
        add(["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds)
        add(["ms", "millisecond", "milliseconds"], UnitDuration.milliseconds)
        add(["µs", "us", "microsecond", "microseconds"], UnitDuration.microseconds)
        add(["ns", "nanosecond", "nanoseconds"], UnitDuration.nanoseconds)
        add(["min", "mins", "minute", "minutes"], UnitDuration.minutes)
        add(["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours)
        add(["d", "day", "days"], day)
        add(["wk", "week", "weeks"], week)
        add(["yr", "year", "years"], year)
        // temperature
        add(["°c", "celsius", "degc"], UnitTemperature.celsius)
        add(["°f", "fahrenheit", "degf"], UnitTemperature.fahrenheit)
        add(["kelvin", "kelvins"], UnitTemperature.kelvin)
        // information (lower-case spellings mean bytes: "500 mb in gb")
        add(["byte", "bytes"], UnitInformationStorage.bytes)
        add(["bit", "bits"], UnitInformationStorage.bits)
        add(["mb", "megabyte", "megabytes"], UnitInformationStorage.megabytes)
        add(["gb", "gigabyte", "gigabytes"], UnitInformationStorage.gigabytes)
        add(["tb", "terabyte", "terabytes"], UnitInformationStorage.terabytes)
        add(["kb", "kilobyte", "kilobytes"], UnitInformationStorage.kilobytes)
        add(["pb", "petabyte", "petabytes"], UnitInformationStorage.petabytes)
        add(["kib"], UnitInformationStorage.kibibytes)
        add(["mib"], UnitInformationStorage.mebibytes)
        add(["gib"], UnitInformationStorage.gibibytes)
        add(["tib"], UnitInformationStorage.tebibytes)
        add(["kbit", "kbps"], UnitInformationStorage.kilobits)
        add(["mbit", "mbps"], UnitInformationStorage.megabits)
        add(["gbit", "gbps"], UnitInformationStorage.gigabits)
        // speed
        add(["m/s", "mps"], UnitSpeed.metersPerSecond)
        add(["km/h", "kmh", "kph", "kmph"], UnitSpeed.kilometersPerHour)
        add(["mph", "mi/h"], UnitSpeed.milesPerHour)
        add(["kn", "kt", "knot", "knots"], UnitSpeed.knots)
        // area
        add(["m²", "m2", "sqm"], UnitArea.squareMeters)
        add(["km²", "km2"], UnitArea.squareKilometers)
        add(["cm²", "cm2"], UnitArea.squareCentimeters)
        add(["ft²", "ft2", "sqft"], UnitArea.squareFeet)
        add(["in²", "in2", "sqin"], UnitArea.squareInches)
        add(["mi²", "mi2", "sqmi"], UnitArea.squareMiles)
        add(["ha", "hectare", "hectares"], UnitArea.hectares)
        add(["acre", "acres", "ac"], UnitArea.acres)
        // volume
        add(["l", "liter", "liters", "litre", "litres"], UnitVolume.liters)
        add(["ml", "milliliter", "milliliters", "millilitre", "millilitres"], UnitVolume.milliliters)
        add(["cl"], UnitVolume.centiliters)
        add(["dl"], UnitVolume.deciliters)
        add(["m³", "m3"], UnitVolume.cubicMeters)
        add(["cm³", "cm3", "cc"], UnitVolume.cubicCentimeters)
        add(["gal", "gallon", "gallons"], UnitVolume.gallons)
        add(["qt", "quart", "quarts"], UnitVolume.quarts)
        add(["pt", "pint", "pints"], UnitVolume.pints)
        add(["cup", "cups"], UnitVolume.cups)
        add(["floz"], UnitVolume.fluidOunces)
        add(["tbsp", "tablespoon", "tablespoons"], UnitVolume.tablespoons)
        add(["tsp", "teaspoon", "teaspoons"], UnitVolume.teaspoons)
        // energy
        add(["joule", "joules"], UnitEnergy.joules)
        add(["kilojoule", "kilojoules"], UnitEnergy.kilojoules)
        add(["cal", "calorie", "calories"], UnitEnergy.calories)
        add(["kcal", "kilocalorie", "kilocalories"], UnitEnergy.kilocalories)
        add(["kwh"], UnitEnergy.kilowattHours)
        // power
        add(["watt", "watts"], UnitPower.watts)
        add(["kilowatt", "kilowatts"], UnitPower.kilowatts)
        add(["hp", "horsepower"], UnitPower.horsepower)
        // pressure
        add(["bar", "bars"], UnitPressure.bars)
        add(["mbar", "millibar", "millibars"], UnitPressure.millibars)
        add(["psi"], UnitPressure.poundsForcePerSquareInch)
        add(["atm", "atmosphere", "atmospheres"], atm)
        add(["mmhg"], UnitPressure.millimetersOfMercury)
        add(["inhg"], UnitPressure.inchesOfMercury)
        add(["hpa"], UnitPressure.hectopascals)
        add(["kpa"], UnitPressure.kilopascals)
        // angle
        add(["°", "deg", "degree", "degrees"], UnitAngle.degrees)
        add(["rad", "radian", "radians"], UnitAngle.radians)
        add(["grad", "gradian", "gradians"], UnitAngle.gradians)
        add(["turn", "turns", "rev", "revs"], turn)
        add(["arcmin", "arcminute", "arcminutes"], UnitAngle.arcMinutes)
        add(["arcsec", "arcsecond", "arcseconds"], UnitAngle.arcSeconds)
        // frequency
        add(["hz", "hertz"], UnitFrequency.hertz)
        add(["khz"], UnitFrequency.kilohertz)
        add(["mhz"], UnitFrequency.megahertz)
        add(["ghz"], UnitFrequency.gigahertz)
        add(["rpm"], rpm)
        return t
    }()

    static func unit(_ word: String) -> Dimension? {
        exact[word] ?? loose[word.lowercased()]
    }

    /// First words of two-word unit names that are not units themselves ("fl oz", "sq ft",
    /// "nautical miles", "light years"): the two words joined name the unit.
    static let phrasePrefixes: Set<String> = ["fl", "sq", "nautical", "light"]

    /// The unit written at `tokens[index]`, over one to three tokens: "km", "km / h", "m ²",
    /// "fl oz", "sq ft". The single place unit phrases are recognised (expressions and targets).
    static func phrase(_ tokens: [CalcToken], at index: Int) -> (unit: Dimension, consumed: Int)? {
        func word(_ k: Int) -> String? {
            if index + k < tokens.count, case .ident(let w) = tokens[index + k] { return w }
            return nil
        }
        guard let first = word(0) else { return nil }
        // "km/h", "m / s"
        if index + 1 < tokens.count, tokens[index + 1] == .op("/"), let second = word(2),
           let u = unit(first + "/" + second) {
            return (u, 3)
        }
        if let second = word(1) {
            // "m ²" written with a separate superscript token
            if second == "²" || second == "³", let u = unit(first + second) { return (u, 2) }
            if phrasePrefixes.contains(first.lowercased()), let u = unit(first + second) { return (u, 2) }
        }
        if let u = unit(first) { return (u, 1) }
        return nil
    }

    /// Currency words → ISO code.
    static let currencyWords: [String: String] = [
        "dollar": "USD", "dollars": "USD", "usd": "USD", "buck": "USD", "bucks": "USD",
        "euro": "EUR", "euros": "EUR", "yen": "JPY", "quid": "GBP",
        "yuan": "CNY", "rmb": "CNY", "won": "KRW", "rupee": "INR", "rupees": "INR", "franc": "CHF", "francs": "CHF",
    ]

    static func currency(_ word: String, rates: (any CalculatorRateProviding)?) -> String? {
        let up = word.uppercased()
        if up.count == 3, CalculatorEngine.knownCurrencies.contains(up) || (rates?.codes.contains(up) ?? false) { return up }
        return currencyWords[word.lowercased()]
    }

    /// Display symbol of a unit for results.
    static func symbol(_ unit: Dimension) -> String {
        if unit == UnitTemperature.celsius { return "°C" }
        if unit == UnitTemperature.fahrenheit { return "°F" }
        if unit == UnitTemperature.kelvin { return "K" }
        if unit == UnitAngle.degrees { return "°" }
        return unit.symbol
    }

    /// The physical quantity of a unit. Not `type(of:)`: Foundation's class constants are private
    /// subclasses (`_NSStatic_NSUnitDuration`), so a custom `UnitDuration(symbol:converter:)` (day)
    /// and `UnitDuration.hours` have different dynamic types although both are durations.
    enum Kind: CaseIterable {
        case length, mass, duration, temperature, information, speed, area, volume, energy, power, pressure, angle, frequency, other
    }

    static func kindOf(_ unit: Dimension) -> Kind {
        switch unit {
        case is UnitLength: return .length
        case is UnitMass: return .mass
        case is UnitDuration: return .duration
        case is UnitTemperature: return .temperature
        case is UnitInformationStorage: return .information
        case is UnitSpeed: return .speed
        case is UnitArea: return .area
        case is UnitVolume: return .volume
        case is UnitEnergy: return .energy
        case is UnitPower: return .power
        case is UnitPressure: return .pressure
        case is UnitAngle: return .angle
        case is UnitFrequency: return .frequency
        default: return .other
        }
    }

    static func sameDimension(_ a: Dimension, _ b: Dimension) -> Bool {
        let k = kindOf(a)
        return k == kindOf(b) && (k != .other || type(of: a) == type(of: b))
    }

    static func convert(_ value: Double, from: Dimension, to: Dimension) -> Double {
        if from == to { return value }
        return to.converter.value(fromBaseUnitValue: from.converter.baseUnitValue(fromValue: value))
    }

    /// A name for the dimension in error messages.
    static func kind(_ unit: Dimension) -> String {
        switch kindOf(unit) {
        case .length: return String(localized: "length")
        case .mass: return String(localized: "mass")
        case .duration: return String(localized: "time")
        case .temperature: return String(localized: "temperature")
        case .information: return String(localized: "data size")
        case .speed: return String(localized: "speed")
        case .area: return String(localized: "area")
        case .volume: return String(localized: "volume")
        case .energy: return String(localized: "energy")
        case .power: return String(localized: "power")
        case .pressure: return String(localized: "pressure")
        case .angle: return String(localized: "angle")
        case .frequency: return String(localized: "frequency")
        case .other: return unit.symbol
        }
    }
}

// MARK: - Evaluator (recursive descent, evaluates while parsing)

enum CalcTarget {
    case unit(Dimension)
    case currency(String)
    case base(Int)
}

struct CalcEvaluator {
    let context: CalculatorContext
    private var tokens: [CalcToken] = []
    private var pos = 0
    /// Base of the first non-decimal literal in the input (0x / 0b / 0o), for the "= 0x…" detail.
    private var literalBase: Int?

    init(context: CalculatorContext) { self.context = context }

    static let conversionWords: Set<String> = ["in", "to", "as", "into"]
    static let functions: Set<String> = [
        "sqrt", "cbrt", "abs", "ln", "log", "log2", "log10", "exp", "sin", "cos", "tan", "asin", "acos", "atan",
        "sinh", "cosh", "tanh", "floor", "ceil", "round", "trunc", "sign", "min", "max",
    ]
    static let constants: [String: Double] = ["pi": .pi, "π": .pi, "tau": 2 * .pi, "τ": 2 * .pi, "e": M_E]

    mutating func run(_ all: [CalcToken]) throws -> CalculatorOutcome {
        // Find the last top-level conversion keyword whose right side is a valid target.
        var depth = 0
        var split: (Int, CalcTarget)?
        for (i, t) in all.enumerated() {
            if t == .op("(") { depth += 1 } else if t == .op(")") { depth -= 1 }
            guard depth == 0, i > 0 else { continue }
            let isKeyword: Bool = {
                if case .ident(let w) = t { return Self.conversionWords.contains(w.lowercased()) }
                return t == .op("->")
            }()
            guard isKeyword, let target = parseTarget(Array(all[(i + 1)...])) else { continue }
            split = (i, target)
        }
        let exprTokens = split.map { Array(all[..<$0.0]) } ?? all
        guard !exprTokens.isEmpty else { throw CalcError(String(localized: "Nothing to convert")) }
        tokens = exprTokens
        pos = 0
        literalBase = nil
        let operand = try parseExpression()
        if pos < tokens.count { throw unexpected(tokens[pos]) }
        return try present(percentResolved(operand), target: split?.1)
    }

    // MARK: Targets

    private func parseTarget(_ ts: [CalcToken]) -> CalcTarget? {
        guard let first = ts.first else { return nil }
        if ts.count == 1 {
            switch first {
            case .currencySymbol(let c): return .currency(c)
            case .ident(let w):
                switch w.lowercased() {
                case "hex", "hexadecimal", "base16": return .base(16)
                case "bin", "binary", "base2": return .base(2)
                case "oct", "octal", "base8": return .base(8)
                case "dec", "decimal", "base10": return .base(10)
                default: break
                }
            default: return nil
            }
        }
        if let p = CalcUnits.phrase(ts, at: 0), p.consumed == ts.count { return .unit(p.unit) }
        if ts.count == 1, case .ident(let w) = first, let c = CalcUnits.currency(w, rates: context.rates) { return .currency(c) }
        return nil
    }

    // MARK: Grammar

    private func peek() -> CalcToken? { pos < tokens.count ? tokens[pos] : nil }
    private mutating func advance() -> CalcToken? { defer { pos += 1 }; return peek() }
    private func isOp(_ s: String) -> Bool { peek() == .op(s) }
    private func isWord(_ s: String) -> Bool {
        if case .ident(let w) = peek() { return w.lowercased() == s }
        return false
    }

    private mutating func parseExpression() throws -> CalcOperand {
        var lhs = try parseTerm()
        while let t = peek(), t == .op("+") || t == .op("-") {
            pos += 1
            let rhs = try parseTerm()
            let sign: Double = t == .op("+") ? 1 : -1
            if rhs.isPercent, case .number(let p) = rhs.value {
                if lhs.isPercent, case .number(let q) = lhs.value {
                    // 5% + 5% = 10% (a percentage of nothing yet)
                    lhs = CalcOperand(value: .number(q + sign * p), isPercent: true)
                } else {
                    // calculator percent: 200 + 10% = 220
                    lhs = CalcOperand(value: scale(lhs.value, by: 1 + sign * p / 100))
                }
            } else {
                lhs = CalcOperand(value: try add(percentResolved(lhs), percentResolved(rhs), sign: sign))
            }
        }
        return lhs
    }

    private mutating func parseTerm() throws -> CalcOperand {
        var lhs = try parsePower()
        while let t = peek() {
            if t == .op("*") || t == .op("/") {
                pos += 1
                let rhs = try parsePower()
                lhs = CalcOperand(value: t == .op("*") ? try multiply(percentResolved(lhs), percentResolved(rhs))
                                                       : try divide(percentResolved(lhs), percentResolved(rhs)))
            } else if t == .op("%") || isWord("mod") {
                // "%" right after an operand that already took its postfix % is modulo: 10 % 3
                pos += 1
                let rhs = try parsePower()
                lhs = CalcOperand(value: try modulo(lhs.value, rhs.value))
            } else if isWord("of"), lhs.isPercent {
                // 15% of 80
                pos += 1
                let rhs = try parsePower()
                guard case .number(let p) = lhs.value else { throw CalcError(String(localized: "Can't evaluate")) }
                lhs = CalcOperand(value: scale(rhs.value, by: p / 100))
            } else if startsOperand(t) {
                // juxtaposition: "3 h 20 min" adds, "2(3+1)" / "2pi" multiplies
                let save = pos
                let rhs = try parsePower()
                switch (lhs.value, rhs.value) {
                case (.measure, .measure), (.money, .money):
                    lhs = CalcOperand(value: try add(lhs.value, rhs.value, sign: 1))
                default:
                    if case .number = rhs.value, case .number = tokens[save] {
                        // a bare number after any operand is a typo or an unfinished quantity, not
                        // a product: "2 3", "$5 3", "3 h 20" (while typing "3 h 20 min" — not 60 h)
                        throw CalcError(String(localized: "Missing operator"))
                    }
                    lhs = CalcOperand(value: try multiply(percentResolved(lhs), percentResolved(rhs)))
                }
            } else {
                break
            }
        }
        return lhs
    }

    private func startsOperand(_ t: CalcToken) -> Bool {
        switch t {
        case .number, .currencySymbol: return true
        case .op("("): return true
        case .ident(let w):
            let l = w.lowercased()
            if Self.conversionWords.contains(l) || l == "of" || l == "mod" { return false }
            return true
        default: return false
        }
    }

    private mutating func parsePower() throws -> CalcOperand {
        let base = try parseUnary()
        guard isOp("^") else { return base }
        pos += 1
        let exponent = try parsePowerRHS()
        return CalcOperand(value: try power(percentResolved(base), percentResolved(exponent)))
    }

    /// Right side of ^: allows a sign (2^-3) and is right associative.
    private mutating func parsePowerRHS() throws -> CalcOperand {
        if isOp("-") || isOp("+") {
            let neg = isOp("-")
            pos += 1
            let v = try parsePowerRHS()
            return neg ? CalcOperand(value: scale(v.value, by: -1), isPercent: v.isPercent) : v
        }
        return try parsePower()
    }

    private mutating func parseUnary() throws -> CalcOperand {
        if isOp("-") || isOp("+") {
            let neg = isOp("-")
            pos += 1
            // -2^2 = -(2^2)
            let v = try parsePower()
            return neg ? CalcOperand(value: scale(v.value, by: -1), isPercent: v.isPercent) : v
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> CalcOperand {
        var operand = try parsePrimary()
        while let t = peek() {
            if t == .op("%") {
                // postfix percent unless an operand follows ("10 % 3" is modulo)
                if let next = pos + 1 < tokens.count ? tokens[pos + 1] : nil, startsOperandStrict(next), !operand.isPercent {
                    break
                }
                guard case .number(let n) = operand.value, !operand.isPercent else { break }
                pos += 1
                operand = CalcOperand(value: .number(n), isPercent: true)
            } else if t == .op("!") {
                pos += 1
                guard case .number(let n) = percentResolved(operand) else { throw CalcError(String(localized: "Factorial needs a number")) }
                operand = CalcOperand(value: .number(try factorial(n)))
            } else if case .ident(let w) = t, case .number(let n) = operand.value, !operand.isPercent,
                      let quantity = quantityAt(w, amount: n) {
                // number followed by a unit / currency: "12 km", "100 usd", "3 h"
                pos += quantity.consumed
                operand = CalcOperand(value: quantity.value)
            } else {
                break
            }
        }
        return operand
    }

    private func startsOperandStrict(_ t: CalcToken) -> Bool {
        switch t {
        case .number, .currencySymbol, .op("("): return true
        case .ident(let w): return Self.functions.contains(w.lowercased()) || Self.constants[w.lowercased()] != nil || w.lowercased() == "ans"
        default: return false
        }
    }

    /// `amount` of the unit or currency at the current token (`word` is its text), with the number
    /// of tokens it takes ("km / h" takes three).
    private func quantityAt(_ word: String, amount: Double) -> (value: CalcValue, consumed: Int)? {
        let l = word.lowercased()
        // "in" is a unit only when it is not the conversion keyword (the conversion split already
        // removed the keyword form); the other keywords are never units
        if Self.conversionWords.contains(l) && l != "in" { return nil }
        if l == "of" || l == "mod" { return nil }
        // a unit name that is also a function only counts when not followed by "("
        if pos + 1 < tokens.count, tokens[pos + 1] == .op("("), Self.functions.contains(l) { return nil }
        if let p = CalcUnits.phrase(tokens, at: pos) { return (.measure(amount, p.unit), p.consumed) }
        if let c = CalcUnits.currency(word, rates: context.rates) { return (.money(amount, c), 1) }
        return nil
    }

    private mutating func parsePrimary() throws -> CalcOperand {
        guard let t = advance() else { throw CalcError(String(localized: "Incomplete expression")) }
        switch t {
        case .number(let v, let base):
            if base != 10, literalBase == nil { literalBase = base }
            return CalcOperand(value: .number(v))
        case .currencySymbol(let code):
            // "$100", "€ 5.50"
            guard case .number(let v, _)? = advance() else { throw CalcError(String(localized: "Expected an amount after the currency sign")) }
            return CalcOperand(value: .money(v, code))
        case .op("("):
            let inner = try parseExpression()
            guard advance() == .op(")") else { throw CalcError(String(localized: "Missing “)”")) }
            return CalcOperand(value: percentResolved(inner))
        case .ident(let w):
            let l = w.lowercased()
            if Self.functions.contains(l) {
                return CalcOperand(value: try parseCall(l))
            }
            if let c = Self.constants[l] ?? Self.constants[w] { return CalcOperand(value: .number(c)) }
            if l == "ans" {
                guard let a = context.ans else { throw CalcError(String(localized: "No previous result")) }
                return CalcOperand(value: .number(a))
            }
            // a bare unit or currency means one of it: "km in mi", "usd in jpy"
            pos -= 1
            if let quantity = quantityAt(w, amount: 1) {
                pos += quantity.consumed
                return CalcOperand(value: quantity.value)
            }
            pos += 1
            throw CalcError(String(localized: "Unknown word “\(w)”"))
        default:
            throw unexpected(t)
        }
    }

    private mutating func parseCall(_ name: String) throws -> CalcValue {
        guard advance() == .op("(") else {
            throw CalcError(String(localized: "\(name) needs parentheses: \(name)(…)"))
        }
        var args: [CalcValue] = []
        if !isOp(")") {
            repeat {
                args.append(percentResolved(try parseExpression()))
            } while advance() == .op(",")
            pos -= 1
        }
        guard advance() == .op(")") else { throw CalcError(String(localized: "Missing “)”")) }
        return try call(name, args)
    }

    private func unexpected(_ t: CalcToken) -> CalcError {
        switch t {
        case .op(let s): return CalcError(String(localized: "Unexpected “\(s)”"))
        case .ident(let w): return CalcError(String(localized: "Unknown word “\(w)”"))
        case .number: return CalcError(String(localized: "Missing operator"))
        case .currencySymbol: return CalcError(String(localized: "Unexpected currency sign"))
        }
    }

    // MARK: Arithmetic

    private func percentResolved(_ o: CalcOperand) -> CalcValue {
        if o.isPercent, case .number(let n) = o.value { return .number(n / 100) }
        return o.value
    }

    private func scale(_ v: CalcValue, by k: Double) -> CalcValue {
        switch v {
        case .number(let n): return .number(n * k)
        case .measure(let n, let u): return .measure(n * k, u)
        case .money(let n, let c): return .money(n * k, c)
        }
    }

    private func add(_ a: CalcValue, _ b: CalcValue, sign: Double) throws -> CalcValue {
        switch (a, b) {
        case (.number(let x), .number(let y)): return .number(x + sign * y)
        case (.measure(let x, let u), .measure(let y, let v)):
            guard CalcUnits.sameDimension(u, v) else { throw incompatible(u, v) }
            return .measure(x + sign * CalcUnits.convert(y, from: v, to: u), u)
        case (.money(let x, let c), .money(let y, let d)):
            return .money(x + sign * (try convertMoney(y, from: d, to: c)), c)
        case (.measure(_, let u), .number), (.number, .measure(_, let u)):
            throw CalcError(String(localized: "Can't add a number and \(CalcUnits.symbol(u))"))
        case (.money(_, let c), .number), (.number, .money(_, let c)):
            throw CalcError(String(localized: "Can't add a number and \(c)"))
        default:
            throw CalcError(String(localized: "Can't add money and units"))
        }
    }

    private func multiply(_ a: CalcValue, _ b: CalcValue) throws -> CalcValue {
        switch (a, b) {
        case (.number(let x), _): return scale(b, by: x)
        case (_, .number(let y)): return scale(a, by: y)
        default: throw CalcError(String(localized: "Can't multiply two quantities"))
        }
    }

    private func divide(_ a: CalcValue, _ b: CalcValue) throws -> CalcValue {
        switch (a, b) {
        case (_, .number(let y)):
            guard y != 0 else { throw CalcError(String(localized: "Division by zero")) }
            return scale(a, by: 1 / y)
        case (.measure(let x, let u), .measure(let y, let v)):
            guard CalcUnits.sameDimension(u, v) else { throw incompatible(u, v) }
            let d = CalcUnits.convert(y, from: v, to: u)
            guard d != 0 else { throw CalcError(String(localized: "Division by zero")) }
            return .number(x / d)
        case (.money(let x, let c), .money(let y, let d)):
            let yy = try convertMoney(y, from: d, to: c)
            guard yy != 0 else { throw CalcError(String(localized: "Division by zero")) }
            return .number(x / yy)
        default:
            throw CalcError(String(localized: "Can't divide by a quantity"))
        }
    }

    private func modulo(_ a: CalcValue, _ b: CalcValue) throws -> CalcValue {
        guard case .number(let y) = b else { throw CalcError(String(localized: "mod needs a number")) }
        guard y != 0 else { throw CalcError(String(localized: "Division by zero")) }
        switch a {
        case .number(let x): return .number(x - y * (x / y).rounded(.down))
        case .measure(let x, let u): return .measure(x.truncatingRemainder(dividingBy: y), u)
        case .money(let x, let c): return .money(x.truncatingRemainder(dividingBy: y), c)
        }
    }

    private func power(_ a: CalcValue, _ b: CalcValue) throws -> CalcValue {
        guard case .number(let y) = b else { throw CalcError(String(localized: "The exponent must be a number")) }
        guard case .number(let x) = a else { throw CalcError(String(localized: "Can't raise a quantity to a power")) }
        let r = pow(x, y)
        guard !r.isNaN else { throw CalcError(String(localized: "Not a real number")) }
        return .number(r)
    }

    private func factorial(_ n: Double) throws -> Double {
        guard n >= 0 else { throw CalcError(String(localized: "Factorial of a negative number")) }
        if n == n.rounded(), n <= 170 {
            return (1...max(Int(n), 1)).reduce(1.0) { $0 * Double($1) }
        }
        return tgamma(n + 1)
    }

    private func incompatible(_ u: Dimension, _ v: Dimension) -> CalcError {
        CalcError(String(localized: "Can't combine \(CalcUnits.kind(u)) and \(CalcUnits.kind(v))"))
    }

    private func convertMoney(_ amount: Double, from: String, to: String) throws -> Double {
        if from == to { return amount }
        guard let rates = context.rates else { throw CalcError(String(localized: "Exchange rates unavailable (offline)")) }
        guard let r = rates.rate(from: from, to: to) else { throw CalcError(String(localized: "No rate for \(from) → \(to)")) }
        return amount * r
    }

    private func call(_ name: String, _ args: [CalcValue]) throws -> CalcValue {
        if name == "min" || name == "max" {
            guard !args.isEmpty else { throw CalcError(String(localized: "\(name) needs at least one value")) }
            let nums = try args.map { v -> Double in
                guard case .number(let n) = v else { throw CalcError(String(localized: "\(name) takes numbers")) }
                return n
            }
            return .number(name == "min" ? nums.min()! : nums.max()!)
        }
        guard args.count == 1 else { throw CalcError(String(localized: "\(name) takes one value")) }
        let x: Double
        switch args[0] {
        case .number(let n): x = n
        case .measure(let n, let u) where u is UnitAngle && ["sin", "cos", "tan"].contains(name):
            x = CalcUnits.convert(n, from: u, to: UnitAngle.radians)
        case .measure(let n, let u) where ["abs", "floor", "ceil", "round", "trunc"].contains(name):
            return .measure(try call(name, [.number(n)]).magnitude, u)
        default:
            throw CalcError(String(localized: "\(name) takes a number"))
        }
        let r: Double
        switch name {
        case "sqrt": r = x.squareRoot()
        case "cbrt": r = cbrt(x)
        case "abs": r = abs(x)
        case "ln": r = Foundation.log(x)
        case "log", "log10": r = log10(x)
        case "log2": r = Foundation.log2(x)
        case "exp": r = Foundation.exp(x)
        case "sin": r = cleanTrig(Foundation.sin(x))
        case "cos": r = cleanTrig(Foundation.cos(x))
        case "tan": r = Foundation.tan(x)
        case "asin": r = Foundation.asin(x)
        case "acos": r = Foundation.acos(x)
        case "atan": r = Foundation.atan(x)
        case "sinh": r = Foundation.sinh(x)
        case "cosh": r = Foundation.cosh(x)
        case "tanh": r = Foundation.tanh(x)
        case "floor": r = x.rounded(.down)
        case "ceil": r = x.rounded(.up)
        case "round": r = x.rounded()
        case "trunc": r = x.rounded(.towardZero)
        case "sign": r = x > 0 ? 1 : x < 0 ? -1 : 0
        default: throw CalcError(String(localized: "Unknown word “\(name)”"))
        }
        guard !r.isNaN else { throw CalcError(String(localized: "Not a real number")) }
        return .number(r)
    }

    /// sin(π) = 1.2e-16 → 0.
    private func cleanTrig(_ v: Double) -> Double { abs(v) < 1e-15 ? 0 : v }

    // MARK: Presentation

    private func present(_ value: CalcValue, target: CalcTarget?) throws -> CalculatorOutcome {
        let fmt = CalculatorFormatter(digits: context.decimalDigits, locale: context.locale)
        guard value.magnitude.isFinite else { throw CalcError(String(localized: "Result is too large")) }
        switch (value, target) {
        case (.number(let n), nil):
            var detail: String?
            if let b = literalBase, let s = fmt.based(n, base: b) { detail = "= " + s }
            return .result(CalculatorResult(display: fmt.number(n), detail: detail, number: n))
        case (.number(let n), .base(let b)):
            guard let s = fmt.based(n, base: b) else { throw CalcError(String(localized: "Base conversion needs a whole number")) }
            return .result(CalculatorResult(display: s, detail: b == 10 ? nil : "= " + fmt.number(n), number: n))
        case (.number, .unit(let u)):
            throw CalcError(String(localized: "Add a unit to convert to \(CalcUnits.symbol(u))"))
        case (.number, .currency(let c)):
            throw CalcError(String(localized: "Add a currency to convert to \(c)"))
        case (.measure(let n, let u), nil):
            return .result(CalculatorResult(display: fmt.measure(n, u), number: n))
        case (.measure(let n, let u), .unit(let v)):
            guard CalcUnits.sameDimension(u, v) else { throw incompatible(u, v) }
            let r = CalcUnits.convert(n, from: u, to: v)
            return .result(CalculatorResult(display: fmt.measure(r, v), number: r))
        case (.measure(let n, let u), .base(let b)):
            guard let s = fmt.based(n, base: b) else { throw CalcError(String(localized: "Base conversion needs a whole number")) }
            return .result(CalculatorResult(display: s + " " + CalcUnits.symbol(u), number: n))
        case (.money(let n, let c), nil):
            // a bare amount converts to the default pair ("100 usd" → JPY)
            let to = c == context.defaultTargetCurrency ? context.defaultSourceCurrency : context.defaultTargetCurrency
            if to == c { return .result(CalculatorResult(display: fmt.money(n, c), number: n, usesCurrency: true)) }
            return try presentMoney(n, from: c, to: to, fmt: fmt)
        case (.money(let n, let c), .currency(let to)):
            return try presentMoney(n, from: c, to: to, fmt: fmt)
        case (.money, .unit(let u)):
            throw CalcError(String(localized: "Can't convert money to \(CalcUnits.symbol(u))"))
        case (.measure(_, let u), .currency):
            throw CalcError(String(localized: "Can't convert \(CalcUnits.symbol(u)) to money"))
        case (.money, .base):
            throw CalcError(String(localized: "Base conversion needs a whole number"))
        }
    }

    private func presentMoney(_ n: Double, from: String, to: String, fmt: CalculatorFormatter) throws -> CalculatorOutcome {
        let r = try convertMoney(n, from: from, to: to)
        var detail: String?
        if from != to, let rates = context.rates, let rate = rates.rate(from: from, to: to) {
            detail = "1 \(from) = \(fmt.number(rate, maxDigits: max(context.decimalDigits, 4))) \(to) · \(rates.date)"
        }
        return .result(CalculatorResult(display: fmt.money(r, to), detail: detail, number: r, usesCurrency: true))
    }
}

// MARK: - Formatting

struct CalculatorFormatter {
    var digits: Int
    var locale: Locale

    func number(_ n: Double, maxDigits: Int? = nil) -> String {
        let digits = maxDigits ?? self.digits
        if n == 0 { return "0" }
        let a = abs(n)
        if a >= 1e15 || a < pow(10, -Double(max(digits, 1))) {
            let f = NumberFormatter()
            f.locale = locale
            f.numberStyle = .scientific
            f.maximumFractionDigits = max(min(digits, 10), 1)
            f.exponentSymbol = "e"
            return f.string(from: n as NSNumber) ?? "\(n)"
        }
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = max(0, min(digits, 15))
        f.roundingMode = .halfEven
        return f.string(from: n as NSNumber) ?? "\(n)"
    }

    func measure(_ n: Double, _ unit: Dimension) -> String {
        let sym = CalcUnits.symbol(unit)
        if sym == "°" || sym == "°C" || sym == "°F" { return number(n) + sym }
        return number(n) + " " + sym
    }

    /// ISO 4217 minor-unit digits of `code` (JPY 0, EUR 2, …; locale-independent).
    static func currencyFractionDigits(_ code: String) -> Int {
        let c = NumberFormatter()
        c.locale = Locale(identifier: "en_US_POSIX")
        c.numberStyle = .currency
        c.currencyCode = code
        return c.maximumFractionDigits
    }

    /// "15,000 JPY", "90.00 EUR": the currency's own fraction digits (capped by the setting).
    func money(_ n: Double, _ code: String) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        let fraction = min(Self.currencyFractionDigits(code), max(digits, 0))
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        return (f.string(from: n as NSNumber) ?? "\(n)") + " " + code
    }

    /// "0xFF" / "0b1010" / "0o17" / decimal; nil if `n` is not a whole number in Int64 range.
    func based(_ n: Double, base: Int) -> String? {
        guard n.isFinite, n == n.rounded(), abs(n) < 9.2e18 else { return nil }
        let i = Int64(n)
        let magnitude = String(i.magnitude, radix: base).uppercased()
        let sign = i < 0 ? "-" : ""
        switch base {
        case 16: return sign + "0x" + magnitude
        case 2: return sign + "0b" + grouped(magnitude, by: 4)
        case 8: return sign + "0o" + magnitude
        default: return number(n)
        }
    }

    private func grouped(_ s: String, by n: Int) -> String {
        guard s.count > n else { return s }
        var out = ""
        for (i, c) in s.reversed().enumerated() {
            if i > 0 && i % n == 0 { out.append(" ") }
            out.append(c)
        }
        return String(out.reversed())
    }
}

// MARK: - Time zones

enum CalcTimeQuery {
    // "15:00 JST in PST", "3pm EST to Tokyo", "9:30am in UTC+9", "now in London", "time in PST"
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(?:(now|time)|(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?)\s*(?:([A-Za-z_/]+(?:[+-]\d{1,2}(?::?\d{2})?)?)\s+)?(?:in|to|->)\s+(.+?)\s*$"#,
        options: [.caseInsensitive])

    static func evaluate(_ text: String, context: CalculatorContext) -> CalculatorOutcome? {
        let ns = text as NSString
        guard let m = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let isNow = group(1) != nil
        let hasColon = group(3) != nil, meridiem = group(4)?.lowercased().replacingOccurrences(of: ".", with: "")
        // a bare number ("15 in hex", "12 in cm") is not a time: need hh:mm, am/pm or now
        guard isNow || hasColon || meridiem != nil else { return nil }
        let local = context.localTimeZone
        guard let targetText = group(6) else { return nil }
        guard let target = zone(targetText, local: local) else {
            // "15:00 in cm", "3pm in cm": certainly a time, but the target is no zone
            return .error(String(localized: "Unknown time zone “\(targetText)”"))
        }
        let source: TimeZone
        if let s = group(5) {
            guard let z = zone(s, local: local) else { return .error(String(localized: "Unknown time zone “\(s)”")) }
            source = z
        } else {
            source = local
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = source
        let date: Date
        if isNow {
            date = context.now
        } else {
            guard var hour = Int(group(2) ?? ""), let minute = Int(group(3) ?? "0"), minute < 60 else {
                return .error(String(localized: "Invalid time"))
            }
            if let mer = meridiem {
                guard (1...12).contains(hour) else { return .error(String(localized: "Invalid time")) }
                if mer == "am" { hour = hour == 12 ? 0 : hour } else { hour = hour == 12 ? 12 : hour + 12 }
            }
            guard (0...23).contains(hour) else { return .error(String(localized: "Invalid time")) }
            var comps = cal.dateComponents([.year, .month, .day], from: context.now)
            comps.hour = hour
            comps.minute = minute
            guard let d = cal.date(from: comps) else { return .error(String(localized: "Invalid time")) }
            date = d
        }
        let f = DateFormatter()
        f.locale = context.locale
        f.timeZone = target
        f.setLocalizedDateFormatFromTemplate("jmm")
        var display = "\(f.string(from: date)) \(name(of: target, at: date))"
        // day shift between the source day and the target day
        var tcal = Calendar(identifier: .gregorian)
        tcal.timeZone = target
        let sourceDay = cal.dateComponents([.year, .month, .day], from: date)
        let targetDay = tcal.dateComponents([.year, .month, .day], from: date)
        if let s = cal.date(from: sourceDay), let t = cal.date(from: targetDay) {
            let shift = cal.dateComponents([.day], from: s, to: t).day ?? 0
            if shift == 1 { display += " " + String(localized: "(next day)") }
            if shift == -1 { display += " " + String(localized: "(previous day)") }
        }
        let sf = DateFormatter()
        sf.locale = context.locale
        sf.timeZone = source
        sf.setLocalizedDateFormatFromTemplate("EEEjmm")
        let detail = "\(sf.string(from: date)) \(name(of: source, at: date)) → \(target.identifier)"
        return .result(CalculatorResult(display: display, detail: detail))
    }

    /// "PDT", "CEST"; for zones Foundation only names "GMT+9" the city ("Tokyo"); offsets as "UTC+5:30".
    static func name(of zone: TimeZone, at date: Date) -> String {
        let abbr = zone.abbreviation(for: date) ?? zone.identifier
        guard abbr.hasPrefix("GMT") else { return abbr }
        if zone.identifier.contains("/"), let city = zone.identifier.split(separator: "/").last {
            return city.replacingOccurrences(of: "_", with: " ")
        }
        if zone.identifier == "UTC" || zone.identifier == "GMT" { return "UTC" }
        return abbr.replacingOccurrences(of: "GMT", with: "UTC")
    }

    /// The zone named by `raw`; "local" / "here" is `local`.
    static func zone(_ raw: String, local: TimeZone = .current) -> TimeZone? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let up = s.uppercased()
        if up == "LOCAL" || up == "HERE" { return local }
        if up == "UTC" || up == "GMT" || up == "Z" { return TimeZone(identifier: "UTC") }
        // UTC+9, GMT-5:30, UTC+0530
        if let m = offsetPattern.firstMatch(in: up, range: NSRange(location: 0, length: (up as NSString).length)) {
            let ns = up as NSString
            let sign = ns.substring(with: m.range(at: 1)) == "-" ? -1 : 1
            let h = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let mm = m.range(at: 3).location == NSNotFound ? 0 : Int(ns.substring(with: m.range(at: 3))) ?? 0
            guard h <= 14, mm < 60 else { return nil }
            return TimeZone(secondsFromGMT: sign * (h * 3600 + mm * 60))
        }
        if s.count <= 5, s.allSatisfy(\.isLetter), let z = extraAbbreviations[up].flatMap(TimeZone.init(identifier:)) ?? TimeZone(abbreviation: up) {
            return z
        }
        if let z = TimeZone(identifier: s) { return z }
        // city: "tokyo", "new york", "los_angeles"
        let key = s.lowercased().replacingOccurrences(of: " ", with: "_")
        if let id = TimeZone.knownTimeZoneIdentifiers.first(where: { $0.split(separator: "/").last?.lowercased() == key }) {
            return TimeZone(identifier: id)
        }
        if let id = cityAliases[key] { return TimeZone(identifier: id) }
        return nil
    }

    private static let offsetPattern = try! NSRegularExpression(pattern: #"^(?:UTC|GMT)([+-])(\d{1,2})(?::?(\d{2}))?$"#)

    /// Abbreviations Foundation does not map (or maps unexpectedly).
    private static let extraAbbreviations: [String: String] = [
        "PST": "America/Los_Angeles", "PDT": "America/Los_Angeles", "PT": "America/Los_Angeles",
        "MST": "America/Denver", "MDT": "America/Denver", "MT": "America/Denver",
        "CST": "America/Chicago", "CDT": "America/Chicago", "CT": "America/Chicago",
        "EST": "America/New_York", "EDT": "America/New_York", "ET": "America/New_York",
        "AKST": "America/Anchorage", "HST": "Pacific/Honolulu",
        "JST": "Asia/Tokyo", "KST": "Asia/Seoul", "IST": "Asia/Kolkata", "SGT": "Asia/Singapore",
        "HKT": "Asia/Hong_Kong", "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney",
        "CET": "Europe/Paris", "CEST": "Europe/Paris", "EET": "Europe/Athens", "WET": "Europe/Lisbon",
        "BST": "Europe/London", "NZST": "Pacific/Auckland",
    ]

    private static let cityAliases: [String: String] = [
        "nyc": "America/New_York", "sf": "America/Los_Angeles", "san_francisco": "America/Los_Angeles",
        "la": "America/Los_Angeles", "seattle": "America/Los_Angeles", "boston": "America/New_York",
        "washington": "America/New_York", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo", "beijing": "Asia/Shanghai",
        "delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "munich": "Europe/Berlin", "san_jose": "America/Los_Angeles",
    ]
}
