// F4 automation surface: parsing of dynamicnotch:// URLs (AutomationCommand) and the policy of
// CommandRouter (with fake actions — nothing here touches a manager, the SMC or the notch).
//   swift test --filter Automation
import Foundation
import Testing
@testable import DynamicNotchApp

private func parse(_ s: String) -> Result<AutomationCommand, AutomationError> { AutomationCommand.parse(s) }

private func command(_ s: String) -> AutomationCommand? {
    if case .success(let c) = parse(s) { return c }
    return nil
}

private func error(_ s: String) -> AutomationError? {
    if case .failure(let e) = parse(s) { return e }
    return nil
}

// MARK: - Parsing

@Suite("AutomationCommand parsing")
struct AutomationCommandParseTests {

    @Test func profileSlug() {
        #expect(command("dynamicnotch://profile/boost") == .fanProfile(.builtIn(.boost)))
    }

    @Test func profileDefaultNameWithSpaces() {
        #expect(command("dynamicnotch://profile/Constant%20Quiet") == .fanProfile(.builtIn(.constantQuiet)))
    }

    @Test(arguments: [
        ("automatic", FanProfileChoice.automatic), ("constant-quiet", .constantQuiet), ("constant_high", .constantHigh),
        ("max", .max), ("custom-1", .custom1), ("Custom%202", .custom2), ("custom2", .custom2), ("BOOST", .boost),
    ])
    func profileCanonicalSlugs(raw: String, expected: FanProfileChoice) {
        #expect(command("dynamicnotch://profile/\(raw)") == .fanProfile(.builtIn(expected)))
    }

    /// Short aliases parse as names, so a renamed custom slot can take them (aliasFallback otherwise).
    @Test(arguments: [
        ("auto", FanProfileChoice.automatic), ("smc", .automatic), ("quiet", .constantQuiet), ("HIGH", .constantHigh),
        ("maximum", .max), ("full", .max),
    ])
    func profileAliases(raw: String, expected: FanProfileChoice) {
        guard case .fanProfile(let reference)? = command("dynamicnotch://profile/\(raw)") else {
            Issue.record("\(raw) must parse as a profile command"); return
        }
        #expect(reference == .name(raw))
        #expect(reference.aliasFallback == expected)
    }

    @Test func profileUUID() {
        let id = UUID(uuidString: "6F1A0000-0000-4000-8000-000000000021")!
        #expect(command("dynamicnotch://profile/\(id.uuidString.lowercased())") == .fanProfile(.id(id)))
    }

    @Test func profileCustomName() {
        #expect(command("dynamicnotch://profile/Late%20Night") == .fanProfile(.name("Late Night")))
    }

    @Test func profileNameWithEncodedSlash() {
        #expect(command("dynamicnotch://profile/Work%2FHome") == .fanProfile(.name("Work/Home")))
    }

    @Test func profileMissingName() {
        #expect(error("dynamicnotch://profile") == .missingArgument("profile name or id"))
        #expect(error("dynamicnotch://profile/%20") == .missingArgument("profile name or id"))
    }

    @Test func fanAuto() {
        #expect(command("dynamicnotch://fan/auto") == .fanAutomatic)
        #expect(command("dynamicnotch://fan/automatic") == .fanAutomatic)
    }

    @Test func fanUnknownAction() {
        #expect(error("dynamicnotch://fan/max") == .unknownCommand("fan/max"))
        #expect(error("dynamicnotch://fan") == .missingArgument("fan action (auto)"))
    }

    @Test func timerStartMinutesAndLabel() {
        #expect(command("dynamicnotch://timer/start?minutes=25&label=Tea") == .timerStart(seconds: 1500, label: "Tea"))
    }

    @Test func timerStartFractionalMinutesAndSeconds() {
        #expect(command("dynamicnotch://timer/start?minutes=1.5&seconds=10") == .timerStart(seconds: 100, label: ""))
        #expect(command("dynamicnotch://timer/start?hours=1&minutes=30") == .timerStart(seconds: 5400, label: ""))
    }

    @Test func timerStartPositionalMinutes() {
        #expect(command("dynamicnotch://timer/start/10") == .timerStart(seconds: 600, label: ""))
    }

    @Test func timerStartLabelIsDecodedAndTrimmed() {
        #expect(command("dynamicnotch://timer/start?minutes=3&label=%20Green%20tea%20%F0%9F%8D%B5%20")
                == .timerStart(seconds: 180, label: "Green tea 🍵"))
    }

    @Test func timerStartQueryNamesAreCaseInsensitive() {
        #expect(command("dynamicnotch://timer/start?MINUTES=2&Label=Eggs") == .timerStart(seconds: 120, label: "Eggs"))
    }

    @Test func timerStartRequiresDuration() {
        #expect(error("dynamicnotch://timer/start") == .missingArgument("timer duration (minutes=…)"))
        #expect(error("dynamicnotch://timer/start?label=Tea") == .missingArgument("timer duration (minutes=…)"))
    }

    @Test func timerStartRejectsBadNumbers() {
        #expect(error("dynamicnotch://timer/start?minutes=abc") == .invalidArgument(name: "minutes", value: "abc"))
        #expect(error("dynamicnotch://timer/start?minutes=-5") == .invalidArgument(name: "minutes", value: "-5"))
        #expect(error("dynamicnotch://timer/start?minutes=nan") == .invalidArgument(name: "minutes", value: "nan"))
    }

    /// Values that overflow Int (or +inf after scaling) are rejected, not trapped on.
    @Test(arguments: ["minutes=1e300", "hours=1e16", "minutes=1e308", "seconds=1e308&minutes=1e308",
                      "seconds=9223372036854775807", "hours=24"])
    func timerStartRejectsHugeDurations(query: String) {
        if case .invalidArgument(let name, _)? = error("dynamicnotch://timer/start?\(query)") { #expect(name == "duration") }
        else { Issue.record("\(query) must be rejected as an invalid duration") }
    }

    @Test func timerStartRoundsToTheLimit() {
        #expect(command("dynamicnotch://timer/start?seconds=86399.4") == .timerStart(seconds: 86399, label: ""))
        #expect(command("dynamicnotch://timer/start?seconds=0.6") == .timerStart(seconds: 1, label: ""))
        if case .invalidArgument? = error("dynamicnotch://timer/start?seconds=0.4") {} else { Issue.record("0.4 s rounds to 0") }
        if case .invalidArgument? = error("dynamicnotch://timer/start?seconds=86399.6") {} else { Issue.record("rounds past 23:59:59") }
    }

    @Test func timerStartBounds() {
        #expect(command("dynamicnotch://timer/start?seconds=1") == .timerStart(seconds: 1, label: ""))
        #expect(command("dynamicnotch://timer/start?seconds=86399") == .timerStart(seconds: 86399, label: ""))
        if case .invalidArgument(let name, _)? = error("dynamicnotch://timer/start?minutes=0") { #expect(name == "duration") }
        else { Issue.record("0 minutes must be rejected") }
        if case .invalidArgument(let name, _)? = error("dynamicnotch://timer/start?minutes=1440") { #expect(name == "duration") }
        else { Issue.record("24 h must be rejected") }
    }

    @Test func timerStartRejectsLongLabel() {
        let label = String(repeating: "a", count: AutomationCommand.maxLabelLength + 1)
        if case .invalidArgument(let name, _)? = error("dynamicnotch://timer/start?minutes=1&label=\(label)") {
            #expect(name == "label")
        } else {
            Issue.record("an over-long label must be rejected")
        }
    }

    @Test func timerStop() {
        #expect(command("dynamicnotch://timer/stop") == .timerStop(label: nil))
        #expect(command("dynamicnotch://timer/stop?label=Tea") == .timerStop(label: "Tea"))
        #expect(command("dynamicnotch://timer/cancel?label=") == .timerStop(label: nil))
    }

    @Test func notchOpenClose() {
        #expect(command("dynamicnotch://notch/open") == .notchOpen)
        #expect(command("dynamicnotch://notch/close") == .notchClose)
        #expect(error("dynamicnotch://notch/toggle") == .unknownCommand("notch/toggle"))
    }

    @Test(arguments: [
        ("keepAwake", NookWidget.keepAwake), ("keep-awake", .keepAwake), ("Keep%20Awake", .keepAwake),
        ("pomodoro", .pomodoro), ("focus", .pomodoro), ("camera", .mirror), ("mirror", .mirror),
        ("todos", .reminders), ("world-clock", .worldClocks), ("COLOR_PICKER", .colorPicker), ("timer", .timer),
    ])
    func widgetShow(raw: String, expected: NookWidget) {
        #expect(command("dynamicnotch://widget/\(raw)/show") == .widgetShow(expected))
    }

    @Test func widgetShowIsTheDefaultVerb() {
        #expect(command("dynamicnotch://widget/calendar") == .widgetShow(.calendar))
    }

    @Test func widgetErrors() {
        #expect(error("dynamicnotch://widget/nope/show") == .unknownWidget("nope"))
        #expect(error("dynamicnotch://widget") == .missingArgument("widget id"))
        #expect(error("dynamicnotch://widget/calendar/hide") == .unknownCommand("widget/calendar/hide"))
    }

    @Test(arguments: [("area", CaptureKind.area), ("window", .window), ("screen", .screen), ("selection", .area)])
    func capture(raw: String, expected: CaptureKind) {
        #expect(command("dynamicnotch://capture/\(raw)") == .capture(expected))
    }

    @Test func captureRejectsRecording() {
        #expect(error("dynamicnotch://capture/recording") == .unknownCommand("capture/recording"))
    }

    @Test func keepAwake() {
        #expect(command("dynamicnotch://keepawake/on") == .keepAwake(.on(nil)))
        #expect(command("dynamicnotch://keep-awake/off") == .keepAwake(.off))
        #expect(command("dynamicnotch://keepAwake/toggle") == .keepAwake(.toggle))
    }

    @Test(arguments: [("15m", KeepAwakeDuration.fifteenMinutes), ("1h", .oneHour), ("120", .twoHours), ("indefinite", .indefinite)])
    func keepAwakeDuration(raw: String, expected: KeepAwakeDuration) {
        #expect(command("dynamicnotch://keepawake/on?duration=\(raw)") == .keepAwake(.on(expected)))
    }

    @Test func keepAwakeBadDuration() {
        #expect(error("dynamicnotch://keepawake/on?duration=3h") == .invalidArgument(name: "duration", value: "3h"))
    }

    @Test func pomodoro() {
        #expect(command("dynamicnotch://pomodoro/start") == .pomodoro(.start))
        #expect(command("dynamicnotch://pomodoro/pause") == .pomodoro(.pause))
        #expect(command("dynamicnotch://focus/skip") == .pomodoro(.skip))
        #expect(command("dynamicnotch://pomodoro/resume") == .pomodoro(.start))
        #expect(error("dynamicnotch://pomodoro/stop") == .unknownCommand("pomodoro/stop"))
    }

    @Test func alternativeURLForms() {
        #expect(command("dynamicnotch:profile/boost") == .fanProfile(.builtIn(.boost)))
        #expect(command("dynamicnotch:///profile/boost") == .fanProfile(.builtIn(.boost)))
        #expect(command("DynamicNotch://Notch/Open/") == .notchOpen)
        #expect(command("  dynamicnotch://notch/close \n") == .notchClose)
    }

    @Test func wrongSchemeOrEmpty() {
        #expect(error("https://example.com/profile/boost") == .unsupportedScheme("https"))
        #expect(error("dynamicnotch://") == .missingArgument("command"))
        #expect(error("dynamicnotch://launch/rockets") == .unknownCommand("launch"))
    }

    @Test func canonicalURLRoundTrips() {
        let commands: [AutomationCommand] = [
            .fanProfile(.builtIn(.constantQuiet)), .fanProfile(.name("Late Night / Work?")), .fanProfile(.name("quiet")),
            .fanProfile(.id(UUID(uuidString: "6F1A0000-0000-4000-8000-000000000022")!)), .fanAutomatic,
            .timerStart(seconds: 1500, label: "Tea & cake"), .timerStart(seconds: 95, label: ""),
            .timerStop(label: nil), .timerStop(label: "Tea"), .notchOpen, .notchClose,
            .widgetShow(.keepAwake), .capture(.window), .keepAwake(.on(.oneHour)), .keepAwake(.on(nil)),
            .keepAwake(.off), .keepAwake(.toggle), .pomodoro(.skip),
        ]
        for c in commands {
            #expect(AutomationCommand.parse(c.url) == .success(c), "\(c.url.absoluteString)")
        }
        #expect(AutomationCommand.fanProfile(.builtIn(.boost)).url.absoluteString == "dynamicnotch://profile/boost")
        #expect(AutomationCommand.timerStart(seconds: 1500, label: "Tea").url.absoluteString
                == "dynamicnotch://timer/start?minutes=25&label=Tea")
    }
}

// MARK: - Profile name matching

@Suite("FanProfileReference matching")
struct FanProfileReferenceTests {
    private let quiet = UUID(uuidString: "6F1A0000-0000-4000-8000-000000000011")!
    private let custom1 = UUID(uuidString: "6F1A0000-0000-4000-8000-000000000021")!
    private var candidates: [(id: UUID, names: [String])] {
        [(quiet, ["Constant Quiet"]), (custom1, ["Late Night", "Late Night"])]
    }

    @Test func nameMatchIsCaseAndDiacriticInsensitive() {
        #expect(FanProfileReference.name("late night").match(in: candidates) == custom1)
        #expect(FanProfileReference.name("  LÁTE NIGHT ").match(in: candidates) == custom1)
        #expect(FanProfileReference.name("Nope").match(in: candidates) == nil)
    }

    @Test func idAndBuiltInMatch() {
        #expect(FanProfileReference.id(custom1).match(in: candidates) == custom1)
        #expect(FanProfileReference.id(UUID()).match(in: candidates) == nil)
        #expect(FanProfileReference.builtIn(.constantQuiet).match(in: candidates) == quiet)
    }

    @Test func slugsWinOverCustomNames() {
        // a custom slot renamed "Boost" is still reached by its own slug / id, not by "boost"
        #expect(FanProfileReference("Boost") == .builtIn(.boost))
        #expect(FanProfileReference("custom-1") == .builtIn(.custom1))
    }

    @Test func customNamesWinOverAliases() {
        // Custom 1 renamed "Quiet": profile/quiet applies it, not Constant Quiet
        let renamed: [(id: UUID, names: [String])] = [(quiet, ["Constant Quiet"]), (custom1, ["Quiet"])]
        let reference = FanProfileReference("quiet")
        #expect(reference.match(in: renamed) == custom1)
        // without such a name the alias still reaches the fixed profile (via aliasFallback)
        #expect(reference.match(in: candidates) == nil)
        #expect(reference.aliasFallback == .constantQuiet)
        #expect(FanProfileReference("Late Night").aliasFallback == nil)
        #expect(FanProfileReference.builtIn(.boost).aliasFallback == nil)
    }
}

// MARK: - Router policy

@MainActor
private final class FakeActions: AutomationActions {
    var nookWidgets: [NookWidget] = [.keepAwake, .pomodoro, .timer]
    var isFanControlAvailable = true
    var isFanControlEnabled = true
    var isCaptureIdle = true
    var allowsAutomationCaptures = false
    var isKeepAwakeActive = false
    var keepAwakeSucceeds = true
    var isPomodoroRunning = false
    var timers: [String] = []
    var log: [String] = []

    func applyFanProfile(_ reference: FanProfileReference) async -> AutomationOutcome {
        log.append("fan:\(reference.description)")
        return .success("Applied \(reference.description)")
    }
    func startTimer(seconds: Int, label: String) { log.append("timer:\(seconds):\(label)"); timers.append(label) }
    func stopTimers(label: String?) -> Int {
        let matching = timers.filter { label == nil || $0.lowercased() == label!.lowercased() }
        timers.removeAll { matching.contains($0) }
        log.append("stop:\(matching.count)")
        return matching.count
    }
    func returnFansToAutomatic() async -> AutomationOutcome {
        log.append("fan:restore")
        return .success("Returned fans to automatic")
    }
    func openNotch() { log.append("open") }
    func closeNotch() { log.append("close") }
    func showWidget(_ widget: NookWidget) { log.append("show:\(widget.rawValue)") }
    func capture(_ kind: CaptureKind) { log.append("capture:\(kind.rawValue)") }
    func keepAwakeOn(_ duration: KeepAwakeDuration?) -> Bool {
        log.append("awake:on:\(duration?.rawValue ?? "last")")
        isKeepAwakeActive = keepAwakeSucceeds
        return keepAwakeSucceeds
    }
    func keepAwakeOff() { log.append("awake:off"); isKeepAwakeActive = false }
    func pomodoro(_ action: PomodoroAction) { log.append("pomodoro:\(action.rawValue)") }
}

private extension CommandRouter {
    /// The URL rules (the stricter source) unless a test says otherwise.
    func perform(_ command: AutomationCommand) async -> AutomationOutcome {
        await perform(command, source: .url)
    }
}

@Suite("CommandRouter policy")
@MainActor
struct CommandRouterTests {

    @Test func fanCommandsNeedFanControl() async {
        let fake = FakeActions()
        let router = CommandRouter(actions: fake)
        fake.isFanControlEnabled = false
        #expect(await router.perform(.fanAutomatic) == .failure(.fanControlDisabled))
        fake.isFanControlAvailable = false
        #expect(await router.perform(.fanProfile(.builtIn(.boost))) == .failure(.fanControlUnavailable))
        #expect(fake.log.isEmpty)
    }

    @Test func fanAutoAlwaysRestoresDefaultControl() async {
        let fake = FakeActions()
        let router = CommandRouter(actions: fake)
        _ = await router.perform(url: URL(string: "dynamicnotch://fan/auto")!)
        _ = await router.perform(url: URL(string: "dynamicnotch://fan/auto")!)   // again: not short-circuited
        _ = await router.perform(url: URL(string: "dynamicnotch://profile/boost")!)
        #expect(fake.log == ["fan:restore", "fan:restore", "fan:Boost"])
    }

    @Test func timers() async {
        let fake = FakeActions()
        let router = CommandRouter(actions: fake)
        #expect(await router.perform(.timerStart(seconds: 1500, label: "Tea")) == .success("Started Tea (25 min)"))
        #expect(await router.perform(.timerStop(label: "coffee")) == .failure(.failed("No timer named “coffee”.")))
        #expect(await router.perform(.timerStop(label: nil)) == .success("Stopped 1 timer"))
        #expect(await router.perform(.timerStop(label: nil)) == .success("No timers running"))
    }

    @Test func widgetShowNeedsTheWidgetInTheNook() async {
        let fake = FakeActions()
        let router = CommandRouter(actions: fake)
        #expect(await router.perform(.widgetShow(.calendar), source: .url) == .failure(.widgetNotInNook("Calendar")))
        #expect(await router.perform(.widgetShow(.timer), source: .url) == .success("Showing Timer"))
        #expect(fake.log == ["show:timer"])
    }

    @Test func keepAwakeOnOffToggle() async {
        let fake = FakeActions()
        let router = CommandRouter(actions: fake)
        #expect(await router.perform(.keepAwake(.toggle)) == .success("Keep Awake on"))
        #expect(await router.perform(.keepAwake(.on(nil))) == .success("Keep Awake is on"))   // not restarted
        #expect(await router.perform(.keepAwake(.on(.twoHours))) == .success("Keep Awake on")) // restarted
        #expect(await router.perform(.keepAwake(.toggle)) == .success("Keep Awake off"))
        #expect(fake.log == ["awake:on:last", "awake:on:twoHours", "awake:off"])
        fake.keepAwakeSucceeds = false
        if case .failure(.failed) = await router.perform(.keepAwake(.on(nil))) {} else { Issue.record("assertion failure must be reported") }
        fake.nookWidgets = []
        #expect(await router.perform(.keepAwake(.off)) == .failure(.widgetNotInNook("Keep Awake")))
    }

    @Test func pomodoroPolicy() async {
        let fake = FakeActions()
        let router = CommandRouter(actions: fake)
        #expect(await router.perform(.pomodoro(.pause)) == .success("Focus session is not running"))
        #expect(await router.perform(.pomodoro(.start)) == .success("Focus session started"))
        fake.isPomodoroRunning = true
        #expect(await router.perform(.pomodoro(.start)) == .success("Focus session already running"))
        #expect(fake.log == ["pomodoro:start"])
        fake.nookWidgets = [.keepAwake]
        #expect(await router.perform(.pomodoro(.skip)) == .failure(.widgetNotInNook("Focus")))
    }

    @Test func captureWhenBusy() async {
        let fake = FakeActions()
        fake.allowsAutomationCaptures = true
        let router = CommandRouter(actions: fake)
        #expect(await router.perform(.capture(.area), source: .url) == .success("Capturing area"))
        fake.isCaptureIdle = false
        #expect(await router.perform(.capture(.screen), source: .url) == .failure(.busy("Capture")))
        #expect(fake.log == ["capture:area"])
    }

    @Test func urlCapturesNeedTheOptIn() async {
        let fake = FakeActions()
        let router = CommandRouter(actions: fake)
        for kind in [CaptureKind.screen, .area, .window] {
            #expect(await router.perform(url: URL(string: "dynamicnotch://capture/\(kind.rawValue)")!) == .failure(.capturesNotAllowed))
        }
        #expect(fake.log.isEmpty)
        // App Intents are the user's own and may prompt; the URL opt-in does not apply to them
        #expect(await router.perform(.capture(.screen), source: .intent) == .success("Capturing screen"))
        fake.allowsAutomationCaptures = true
        fake.isCaptureIdle = true
        #expect(await router.perform(url: URL(string: "dynamicnotch://capture/screen")!) == .success("Capturing screen"))
        #expect(fake.log == ["capture:screen", "capture:screen"])
    }

    @Test func parseErrorsAreReturnedWithoutSideEffects() async {
        let fake = FakeActions()
        let router = CommandRouter(actions: fake)
        #expect(await router.perform(url: URL(string: "dynamicnotch://launch/rockets")!) == .failure(.unknownCommand("launch")))
        #expect(fake.log.isEmpty)
    }

    @Test func durationText() {
        #expect(CommandRouter.duration(1500) == "25 min")
        #expect(CommandRouter.duration(5430) == "1 h 30 min 30 s")
        #expect(CommandRouter.duration(45) == "45 s")
    }
}
