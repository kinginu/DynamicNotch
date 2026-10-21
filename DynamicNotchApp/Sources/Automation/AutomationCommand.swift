// F4 automation surface (2026-10-20): the command model shared by the `dynamicnotch://` URL
// scheme (URLCommandRouter), the App Intents (AutomationIntents.swift) and `dnctl`.
//
// Pure value types (Foundation only, plus the app's NookWidget / CaptureKind / KeepAwakeDuration
// enums) so the parser is unit-testable in the SwiftPM harness (Tests/AutomationTests).
// Execution lives in CommandRouter; docs/automation.md is the user-facing reference.
//
// Grammar (case-insensitive verbs; `-` / `_` are ignored in verbs and slugs):
//
//   dynamicnotch://profile/<slug | uuid | name>
//   dynamicnotch://fan/auto
//   dynamicnotch://timer/start?minutes=<m>&seconds=<s>&label=<text>    (or timer/start/<m>)
//   dynamicnotch://timer/stop[?label=<text>]
//   dynamicnotch://notch/open | notch/close
//   dynamicnotch://widget/<id>/show
//   dynamicnotch://capture/area | capture/window | capture/screen
//   dynamicnotch://keepawake/on[?duration=15m|1h|2h|indefinite] | keepawake/off | keepawake/toggle
//   dynamicnotch://pomodoro/start | pomodoro/pause | pomodoro/skip      (alias: focus/…)
//
// `dynamicnotch:profile/boost` and `dynamicnotch:///profile/boost` parse the same as the `//` form.
import Foundation

// MARK: - Command

enum AutomationCommand: Equatable, Hashable {
    case fanProfile(FanProfileReference)
    case fanAutomatic
    /// `seconds` is 1…`maxTimerSeconds`; `label` is trimmed ("" = the timer's default "Timer").
    case timerStart(seconds: Int, label: String)
    /// nil = every timer; else only the timers whose label matches (case-insensitive).
    case timerStop(label: String?)
    case notchOpen
    case notchClose
    case widgetShow(NookWidget)
    case capture(CaptureKind)
    case keepAwake(KeepAwakeAction)
    case pomodoro(PomodoroAction)

    static let scheme = "dynamicnotch"
    /// The timer wheel's limit (23:59:59).
    static let maxTimerSeconds = 23 * 3600 + 59 * 60 + 59
    /// Longest accepted timer label (longer labels are an error, not truncated).
    static let maxLabelLength = 100
}

enum KeepAwakeAction: Equatable, Hashable {
    /// nil duration = the widget's last-used duration.
    case on(KeepAwakeDuration?)
    case off
    case toggle
}

enum PomodoroAction: String, CaseIterable, Equatable, Hashable {
    case start, pause, skip
}

/// The seven fixed fan profiles (`ProfileStore.fixedProfiles`), by URL slug. The mapping to

enum FanProfileChoice: String, CaseIterable, Equatable, Hashable, Sendable {
    case automatic, constantQuiet, constantHigh, boost, max, custom1, custom2

    /// Canonical URL slug ("constant-quiet").
    var slug: String {
        switch self {
        case .automatic: return "automatic"
        case .constantQuiet: return "constant-quiet"
        case .constantHigh: return "constant-high"
        case .boost: return "boost"
        case .max: return "max"
        case .custom1: return "custom-1"
        case .custom2: return "custom-2"
        }
    }

    /// Default English name (FanProfile.defaultName); a renamed custom slot keeps this slug.
    var defaultName: String {
        switch self {
        case .automatic: return "Automatic"
        case .constantQuiet: return "Constant Quiet"
        case .constantHigh: return "Constant High"
        case .boost: return "Boost"
        case .max: return "Max"
        case .custom1: return "Custom 1"
        case .custom2: return "Custom 2"
        }
    }

    /// Accepts the slug, the default name and short aliases, ignoring case, spaces, `-` and `_`
    /// ("Constant Quiet", "constant_quiet", "quiet", "auto", "custom1", "maximum").
    init?(slug raw: String) {
        if let canonical = Self(canonical: raw) {
            self = canonical
            return
        }
        switch AutomationCommand.normalize(raw) {
        case "auto", "smc": self = .automatic
        case "quiet": self = .constantQuiet
        case "high": self = .constantHigh
        case "maximum", "full": self = .max
        default: return nil
        }
    }

    /// The canonical slug or the default name only (no short aliases), ignoring case, spaces,
    /// `-` and `_` ("constant-quiet", "Constant Quiet", "custom2"; not "quiet").
    init?(canonical raw: String) {
        let key = AutomationCommand.normalize(raw)
        guard let match = Self.allCases.first(where: { AutomationCommand.normalize($0.slug) == key }) else { return nil }
        self = match
    }
}

/// How a `profile/…` command names its profile.
enum FanProfileReference: Equatable, Hashable {
    case builtIn(FanProfileChoice)
    case id(UUID)
    /// A display name (e.g. a renamed custom slot), matched case-insensitively at run time.
    case name(String)

    /// Canonical slugs and default names → `.builtIn`; a UUID → `.id`; anything else, including
    /// the short aliases ("quiet", "auto", "maximum"), → `.name`. A `.name` is matched against the
    /// profiles' display names first and falls back to `aliasFallback`, so a custom slot renamed
    /// "Quiet" wins over the alias for Constant Quiet.
    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let choice = FanProfileChoice(canonical: trimmed) {
            self = .builtIn(choice)
        } else if let uuid = UUID(uuidString: trimmed) {
            self = .id(uuid)
        } else {
            self = .name(trimmed)
        }
    }

    /// For `.name`: the fixed profile its text is a short alias of ("quiet" → Constant Quiet),
    /// used only when no profile has that display name.
    var aliasFallback: FanProfileChoice? {
        if case .name(let name) = self { return FanProfileChoice(slug: name) }
        return nil
    }

    var description: String {
        switch self {
        case .builtIn(let choice): return choice.defaultName
        case .id(let uuid): return uuid.uuidString
        case .name(let name): return name
        }
    }

    /// The id of the first candidate whose id or one of whose names matches (names compared
    /// case- and diacritic-insensitively, surrounding whitespace ignored). `.builtIn` matches the
    /// candidate listing `choice.defaultName` or the slug among its names.
    func match(in candidates: [(id: UUID, names: [String])]) -> UUID? {
        switch self {
        case .id(let uuid):
            return candidates.first { $0.id == uuid }?.id
        case .builtIn(let choice):
            return candidates.first { $0.names.contains { AutomationCommand.normalize($0) == AutomationCommand.normalize(choice.defaultName) } }?.id
        case .name(let name):
            let wanted = Self.fold(name)
            guard !wanted.isEmpty else { return nil }
            return candidates.first { $0.names.contains { Self.fold($0) == wanted } }?.id
        }
    }

    private static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

// MARK: - Errors

enum AutomationError: Error, Equatable, LocalizedError {
    case unsupportedScheme(String)
    case unknownCommand(String)
    case missingArgument(String)
    case invalidArgument(name: String, value: String)
    case unknownWidget(String)
    case widgetNotInNook(String)
    case profileNotFound(String)
    case fanControlUnavailable
    case fanControlDisabled
    case noFans
    case capturesNotAllowed
    case busy(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme(let s): return "Not a dynamicnotch:// URL (\(s))."
        case .unknownCommand(let c): return "Unknown command “\(c)”."
        case .missingArgument(let what): return "Missing \(what)."
        case .invalidArgument(let name, let value): return "Invalid \(name) “\(value)”."
        case .unknownWidget(let id): return "Unknown widget “\(id)”."
        case .widgetNotInNook(let name): return "Add the \(name) widget to the Nook first (Settings ▸ Nook ▸ Widgets)."
        case .profileNotFound(let name): return "No fan profile named “\(name)”."
        case .fanControlUnavailable: return "Fan Control is not available in this build."
        case .fanControlDisabled: return "Fan Control is turned off (Settings ▸ Fan Control)."
        case .noFans: return "No fans found."
        case .capturesNotAllowed: return "Screenshots from URLs are off. Turn on “Allow automation to take screenshots” in Settings ▸ Nook ▸ Widgets ▸ Capture."
        case .busy(let what): return "\(what) is busy."
        case .failed(let message): return message
        }
    }
}

typealias AutomationOutcome = Result<String, AutomationError>

// MARK: - Parsing

extension AutomationCommand {

    /// Lowercased, without spaces, `-`, `_` and `.` ("Keep-Awake" → "keepawake").
    static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { !" -_.".unicodeScalars.contains($0) }.map(Character.init))
    }

    static func parse(_ string: String) -> Result<AutomationCommand, AutomationError> {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return .failure(.invalidArgument(name: "URL", value: trimmed)) }
        return parse(url)
    }

    static func parse(_ url: URL) -> Result<AutomationCommand, AutomationError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidArgument(name: "URL", value: url.absoluteString))
        }
        guard components.scheme?.lowercased() == scheme else {
            return .failure(.unsupportedScheme(components.scheme ?? url.absoluteString))
        }
        // host + path segments; segments are split before percent-decoding so "%2F" stays inside one
        var segments: [String] = []
        if let host = components.percentEncodedHost, !host.isEmpty {
            segments.append(host.removingPercentEncoding ?? host)
        }
        segments += components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name.lowercased()] == nil {
            query[item.name.lowercased()] = item.value ?? ""
        }
        return parse(segments: segments, query: query)
    }

    static func parse(segments: [String], query: [String: String]) -> Result<AutomationCommand, AutomationError> {
        guard let head = segments.first else { return .failure(.missingArgument("command")) }
        let rest = Array(segments.dropFirst())
        let verb = rest.first.map(normalize)

        switch normalize(head) {
        case "profile", "fanprofile":
            let name = rest.joined(separator: "/").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .failure(.missingArgument("profile name or id")) }
            return .success(.fanProfile(FanProfileReference(name)))

        case "fan", "fans":
            switch verb {
            case "auto", "automatic": return .success(.fanAutomatic)
            case nil: return .failure(.missingArgument("fan action (auto)"))
            default: return .failure(.unknownCommand("fan/\(rest[0])"))
            }

        case "timer", "timers":
            switch verb {
            case "start":
                return parseTimerStart(positional: rest.dropFirst().first, query: query)
            case "stop", "cancel":
                let label = query["label"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .success(.timerStop(label: (label?.isEmpty ?? true) ? nil : label))
            case nil: return .failure(.missingArgument("timer action (start, stop)"))
            default: return .failure(.unknownCommand("timer/\(rest[0])"))
            }

        case "notch":
            switch verb {
            case "open", "show": return .success(.notchOpen)
            case "close", "hide": return .success(.notchClose)
            case nil: return .failure(.missingArgument("notch action (open, close)"))
            default: return .failure(.unknownCommand("notch/\(rest[0])"))
            }

        case "widget", "widgets":
            guard let id = rest.first else { return .failure(.missingArgument("widget id")) }
            guard let widget = widget(named: id) else { return .failure(.unknownWidget(id)) }
            switch rest.dropFirst().first.map(normalize) {
            case "show", "open", nil: return .success(.widgetShow(widget))
            case let other?: return .failure(.unknownCommand("widget/\(id)/\(other)"))
            }

        case "capture", "screenshot":
            switch verb {
            case "area", "selection": return .success(.capture(.area))
            case "window": return .success(.capture(.window))
            case "screen", "fullscreen": return .success(.capture(.screen))
            case nil: return .failure(.missingArgument("capture kind (area, window, screen)"))
            default: return .failure(.unknownCommand("capture/\(rest[0])"))
            }

        case "keepawake", "caffeinate":
            switch verb {
            case "on", "start":
                guard let raw = query["duration"], !raw.isEmpty else { return .success(.keepAwake(.on(nil))) }
                guard let duration = keepAwakeDuration(raw) else {
                    return .failure(.invalidArgument(name: "duration", value: raw))
                }
                return .success(.keepAwake(.on(duration)))
            case "off", "stop": return .success(.keepAwake(.off))
            case "toggle": return .success(.keepAwake(.toggle))
            case nil: return .failure(.missingArgument("keep awake action (on, off, toggle)"))
            default: return .failure(.unknownCommand("keepawake/\(rest[0])"))
            }

        case "pomodoro", "focus":
            guard let verb else { return .failure(.missingArgument("pomodoro action (start, pause, skip)")) }
            guard let action = PomodoroAction(rawValue: verb == "resume" ? "start" : verb) else {
                return .failure(.unknownCommand("pomodoro/\(rest[0])"))
            }
            return .success(.pomodoro(action))

        default:
            return .failure(.unknownCommand(head))
        }
    }

    private static func parseTimerStart(positional: String?, query: [String: String]) -> Result<AutomationCommand, AutomationError> {
        var total = 0.0
        var any = false
        for (name, raw) in [("minutes", query["minutes"] ?? positional), ("seconds", query["seconds"]), ("hours", query["hours"])] {
            guard let raw else { continue }
            guard let value = Double(raw.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 0 else {
                return .failure(.invalidArgument(name: name, value: raw))
            }
            any = true
            total += value * (name == "hours" ? 3600 : name == "minutes" ? 60 : 1)
        }
        guard any else { return .failure(.missingArgument("timer duration (minutes=…)")) }
        // Range-check the Double before converting: `Int(_:)` traps on values outside Int's range
        // (minutes=1e300, hours=1e16) and on ±inf (minutes=1e308 × 60).
        let rounded = total.rounded()
        guard rounded.isFinite, rounded >= 1, rounded <= Double(maxTimerSeconds) else {
            let shown = rounded.isFinite && abs(rounded) < 1e15 ? "\(Int64(rounded))" : String(format: "%g", total)
            return .failure(.invalidArgument(name: "duration", value: "\(shown) s (1 s – 23:59:59)"))
        }
        let seconds = Int(rounded)
        let label = (query["label"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count <= maxLabelLength else {
            return .failure(.invalidArgument(name: "label", value: String(label.prefix(20)) + "…"))
        }
        return .success(.timerStart(seconds: seconds, label: label))
    }

    /// A Nook widget by raw value, display name or alias, ignoring case, spaces, `-` and `_`
    /// ("keepAwake", "keep-awake", "Keep Awake", "focus" → Pomodoro, "camera" → mirror).
    static func widget(named raw: String) -> NookWidget? {
        let key = normalize(raw)
        guard !key.isEmpty else { return nil }
        if let match = NookWidget.allCases.first(where: { normalize($0.rawValue) == key || normalize($0.name) == key }) {
            return match
        }
        switch key {
        case "fan", "fans": return NookWidget(rawValue: "fanControl")
        case "todos", "todo": return .reminders
        case "music", "nowplaying": return .media
        case "clocks": return .worldClocks
        case "screenshot": return .capture
        case "colourpicker": return .colorPicker
        default: return nil
        }
    }

    static func keepAwakeDuration(_ raw: String) -> KeepAwakeDuration? {
        switch normalize(raw) {
        case "15m", "15", "15min", "fifteenminutes": return .fifteenMinutes
        case "1h", "60", "60m", "1hour", "onehour": return .oneHour
        case "2h", "120", "120m", "2hours", "twohours": return .twoHours
        case "indefinite", "infinite", "forever", "untilturnedoff", "0": return .indefinite
        default: return nil
        }
    }

    // MARK: Formatting

    /// The canonical URL of this command (parse(url) round-trips to `self`).
    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        var path: [String]
        var items: [URLQueryItem] = []
        switch self {
        case .fanProfile(let ref):
            switch ref {
            case .builtIn(let choice): path = ["profile", choice.slug]
            case .id(let uuid): path = ["profile", uuid.uuidString]
            case .name(let name): path = ["profile", name]
            }
        case .fanAutomatic: path = ["fan", "auto"]
        case .timerStart(let seconds, let label):
            path = ["timer", "start"]
            if seconds % 60 == 0 { items.append(URLQueryItem(name: "minutes", value: "\(seconds / 60)")) }
            else { items.append(URLQueryItem(name: "seconds", value: "\(seconds)")) }
            if !label.isEmpty { items.append(URLQueryItem(name: "label", value: label)) }
        case .timerStop(let label):
            path = ["timer", "stop"]
            if let label { items.append(URLQueryItem(name: "label", value: label)) }
        case .notchOpen: path = ["notch", "open"]
        case .notchClose: path = ["notch", "close"]
        case .widgetShow(let widget): path = ["widget", widget.rawValue, "show"]
        case .capture(let kind): path = ["capture", kind.rawValue]
        case .keepAwake(let action):
            switch action {
            case .on(let duration):
                path = ["keepawake", "on"]
                if let duration { items.append(URLQueryItem(name: "duration", value: Self.durationSlug(duration))) }
            case .off: path = ["keepawake", "off"]
            case .toggle: path = ["keepawake", "toggle"]
            }
        case .pomodoro(let action): path = ["pomodoro", action.rawValue]
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;")
        c.percentEncodedHost = path[0]
        c.percentEncodedPath = "/" + path.dropFirst()
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
            .joined(separator: "/")
        if !items.isEmpty {
            // `queryItems` would leave "&", "=" and "+" in values unescaped
            var queryAllowed = CharacterSet.urlQueryAllowed
            queryAllowed.remove(charactersIn: "&=+?#")
            c.percentEncodedQueryItems = items.map {
                URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: queryAllowed))
            }
        }
        return c.url ?? URL(string: "\(Self.scheme)://\(path.joined(separator: "/"))")!
    }

    static func durationSlug(_ duration: KeepAwakeDuration) -> String {
        switch duration {
        case .fifteenMinutes: return "15m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .indefinite: return "indefinite"
        }
    }
}
