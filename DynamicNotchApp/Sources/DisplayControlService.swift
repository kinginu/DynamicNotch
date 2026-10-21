// Brightness / contrast / volume of the connected displays for the Displays widget
// (2026-10-20). All hardware I/O (DisplayServices, IORegistry, DDC/CI over I2C) runs on one serial
// queue, so a slow or unplugged monitor blocks neither the UI nor other reads, and two DDC messages
// never overlap on a bus. Slider moves are clamped to 0…1 and coalesced per display + control
// (the latest value wins) with a minimum interval between writes (`CoalescingRateLimiter`): DDC/CI
// needs ≥ 50 ms between messages, and monitors' firmware struggles with a flood of Set VCP.
// Runs while a Displays view is visible or the widget is in the Nook (WidgetPresence).
// `DisplayControlCommand` is the automation entry point (`perform(_:)`).
import Foundation
import AppKit
import CoreGraphics
import Observation

enum DisplayControl: String, Codable, CaseIterable, Hashable, Sendable {
    case brightness, contrast, volume
    /// VCP 0x60: listed read-only (switching inputs from the notch would blank the display).
    case input

    var vcpCode: VCPCode {
        switch self {
        case .brightness: return .brightness
        case .contrast:   return .contrast
        case .volume:     return .audioVolume
        case .input:      return .inputSource
        }
    }

    var isSettable: Bool { self != .input }
}

enum DDCStatus: Equatable, Hashable, Sendable {
    /// Built-in display (no DDC).
    case notApplicable
    /// DDC turned off in the settings, or the display is disabled.
    case disabled
    case probing
    case available
    /// No DCPAVServiceProxy for this display, or it did not answer.
    case unavailable(String)
}

struct DisplayControlState: Equatable, Sendable {
    /// 0…1, nil when unknown.
    var brightness: Double?
    var contrast: Double?
    var volume: Double?
    /// VCP 0x60 code (low byte).
    var inputSource: UInt8?
    var maximums: [DisplayControl: UInt16] = [:]
    var capabilities: DDCCapabilities?
    var ddc: DDCStatus = .notApplicable
    /// Brightness came from the registry fallback (built-in, no DisplayServices).
    var brightnessApproximate = false
    var brightnessSettable = false
    var lastRead: Date?

    func value(_ control: DisplayControl) -> Double? {
        switch control {
        case .brightness: return brightness
        case .contrast:   return contrast
        case .volume:     return volume
        case .input:      return nil
        }
    }

    /// Controls the widget can offer for this display.
    func isAvailable(_ control: DisplayControl) -> Bool {
        switch control {
        case .brightness: return brightness != nil
        case .contrast:   return contrast != nil
        // a value alone is not enough: the DELL P3225QE has no speakers but answers VCP 0x62 with 50
        case .volume:     return volume != nil && (capabilities?.supports(.audioVolume) ?? false)
        case .input:      return inputSource != nil
        }
    }

    func isSettable(_ control: DisplayControl) -> Bool {
        switch control {
        case .brightness: return brightnessSettable
        case .contrast, .volume: return ddc == .available && isAvailable(control)
        case .input: return false
        }
    }
}

// MARK: - Rate limiting

/// Per-key "latest value wins" limiter with a minimum interval between sends (pure; the caller
/// owns the clock and the timer).
struct CoalescingRateLimiter<Key: Hashable, Value> {
    var minimumInterval: TimeInterval
    private(set) var pending: [Key: Value] = [:]
    private var lastSent: [Key: Date] = [:]
    private var scheduled: Set<Key> = []

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    /// Stores `value` for `key`. Returns the delay after which `flush(key:now:)` must be called,
    /// or nil when a flush is already scheduled (the new value replaces the pending one).
    /// `interval` overrides `minimumInterval` for this key.
    mutating func submit(_ value: Value, for key: Key, now: Date, interval: TimeInterval? = nil) -> TimeInterval? {
        pending[key] = value
        guard !scheduled.contains(key) else { return nil }
        scheduled.insert(key)
        let since = lastSent[key].map { now.timeIntervalSince($0) } ?? .infinity
        return max(0, (interval ?? minimumInterval) - since)
    }

    /// The value to send now (nil when nothing is pending); records the send time.
    mutating func flush(key: Key, now: Date) -> Value? {
        scheduled.remove(key)
        guard let v = pending.removeValue(forKey: key) else { return nil }
        lastSent[key] = now
        return v
    }

    func isPending(_ key: Key) -> Bool { pending[key] != nil || scheduled.contains(key) }

    /// Time of the last send for `key`.
    func lastSend(_ key: Key) -> Date? { lastSent[key] }
}

// MARK: - Automation

/// A display adjustment for automation (Shortcuts / URL / debug hooks): e.g.
/// `brightness 60%`, `brightness +10% builtin`, `contrast 0.5 main`, `volume -5 external`,
/// `brightness 40 id:3`, `brightness 70 name:DELL`. Values are percentages when > 1 or written
/// with "%", fractions otherwise ("0.5" = 50 %, "1" = 100 %). Input switching is not offered.
struct DisplayControlCommand: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    enum Target: Codable, Equatable, Hashable, Sendable {
        case all, builtIn, main, external
        case id(UInt32)
        /// Case-insensitive substring of the display name.
        case name(String)
    }

    enum Action: Codable, Equatable, Hashable, Sendable {
        /// Absolute value 0…1.
        case set(Double)
        /// Relative change (−1…1).
        case adjust(Double)
    }

    var control: DisplayControl
    var action: Action
    var target: Target = .all

    init(control: DisplayControl, action: Action, target: Target = .all) {
        self.control = control
        self.action = action
        self.target = target
    }

    init?(parsing text: String) {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2, words.count <= 3,
              let control = DisplayControl(rawValue: words[0].lowercased()), control.isSettable,
              let action = Self.parseAction(words[1]) else { return nil }
        var target = Target.all
        if words.count == 3 {
            guard let t = Self.parseTarget(words[2]) else { return nil }
            target = t
        }
        self.init(control: control, action: action, target: target)
    }

    private static func parseAction(_ s: String) -> Action? {
        var t = s
        let relative = t.hasPrefix("+") || t.hasPrefix("-")
        let percent = t.hasSuffix("%")
        if percent { t.removeLast() }
        guard let n = Double(t), n.isFinite else { return nil }
        let magnitude = abs(n)
        let fraction = (percent || magnitude > 1 ? n / 100 : n)
        if relative { return .adjust(min(max(fraction, -1), 1)) }
        guard fraction >= 0 else { return nil }
        return .set(min(fraction, 1))
    }

    private static func parseTarget(_ s: String) -> Target? {
        switch s.lowercased() {
        case "all": return .all
        case "builtin", "built-in", "internal": return .builtIn
        case "main": return .main
        case "external", "externals": return .external
        default:
            if s.lowercased().hasPrefix("id:"), let n = UInt32(s.dropFirst(3)) { return .id(n) }
            if s.lowercased().hasPrefix("name:"), s.count > 5 { return .name(String(s.dropFirst(5))) }
            return nil
        }
    }

    func matches(_ d: DisplayInfo) -> Bool {
        switch target {
        case .all: return true
        case .builtIn: return d.isBuiltIn
        case .main: return d.isMain
        case .external: return !d.isBuiltIn
        case .id(let n): return d.id == n
        case .name(let s): return d.name.localizedCaseInsensitiveContains(s)
        }
    }

    /// The new value for a display whose current value is `current`.
    func resolvedValue(current: Double?) -> Double? {
        switch action {
        case .set(let v): return min(max(v, 0), 1)
        case .adjust(let d):
            guard let c = current else { return nil }
            return min(max(c + d, 0), 1)
        }
    }

    var description: String {
        let value: String
        switch action {
        case .set(let v): value = "\(Int((v * 100).rounded()))%"
        case .adjust(let d): value = (d >= 0 ? "+" : "") + "\(Int((d * 100).rounded()))%"
        }
        let t: String
        switch target {
        case .all: t = "all"
        case .builtIn: t = "builtin"
        case .main: t = "main"
        case .external: t = "external"
        case .id(let n): t = "id:\(n)"
        case .name(let s): t = "name:\(s)"
        }
        return "\(control.rawValue) \(value) \(t)"
    }
}

// MARK: - Service

@MainActor
@Observable
final class DisplayControlService {
    static let shared = DisplayControlService()

    private(set) var displays: [DisplayInfo] = []
    private(set) var states: [CGDirectDisplayID: DisplayControlState] = [:]
    private(set) var lastRefresh: Date?

    /// Minimum time between two writes of the same control of one display.
    static let ddcWriteInterval: TimeInterval = 0.1
    static let builtInWriteInterval: TimeInterval = 0.03
    /// A control that was just written is not overwritten by a read for this long (monitors
    /// report the old value for a moment).
    static let readHoldOff: TimeInterval = 1.5
    /// Built-in brightness changes with the keys / ambient light; DDC reads are slow, so they run
    /// at the settings' interval only.
    static let builtInPollInterval: TimeInterval = 2
    /// A capabilities read that failed (or had no vcp() list) is retried at most this often: a
    /// full read is up to 64 fragments with retries and blocks the I/O queue for seconds.
    static let capabilitiesRetryInterval: TimeInterval = 300

    struct WriteKey: Hashable { var display: CGDirectDisplayID; var control: DisplayControl }

    @ObservationIgnored let hardware: DisplayHardware
    @ObservationIgnored private let settingsProvider: () -> DisplaysWidgetSettings
    @ObservationIgnored private var limiter = CoalescingRateLimiter<WriteKey, Double>(minimumInterval: DisplayControlService.ddcWriteInterval)
    @ObservationIgnored private var channels: [CGDirectDisplayID: DDCChannel] = [:]
    @ObservationIgnored private var capabilitiesCache: [String: DDCCapabilities] = [:]
    /// When a display's capabilities read last failed (keyed like `capabilitiesCache`).
    @ObservationIgnored private var capabilitiesFailedAt: [String: Date] = [:]
    /// The external displays (and DDC setting) the channel map was built for: it is rebuilt only
    /// when these change (or after wake / a screen change), not because some display (Sidecar,
    /// AirPlay, DisplayLink) never gets a channel.
    @ObservationIgnored private var channelDisplayIDs: Set<CGDirectDisplayID> = []
    @ObservationIgnored private var channelsBuiltWithDDC = false
    /// Per-control write counters and completion times: a read that started before a write
    /// finished must not replace the written value (the hold-off counts from completion).
    @ObservationIgnored private var writeGeneration: [WriteKey: Int] = [:]
    @ObservationIgnored private var writesRunning: [WriteKey: Int] = [:]
    @ObservationIgnored private var writeCompletedAt: [WriteKey: Date] = [:]
    @ObservationIgnored private var refreshWriteGenerations: [WriteKey: Int] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var builtInTimer: Timer?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    /// Runs while a Displays view is visible or the widget is in the Nook.
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(.displays, label: "Displays",
                                      onNeeded: { [unowned self] in self.install() },
                                      onIdle: { [unowned self] in self.tearDown() })
        // monitors need a moment after wake before they answer DDC/CI
        presence.onWake(after: 3) { [unowned self] in
            self.channelsStale = true
            self.refresh()
        }
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in self.timer != nil || self.builtInTimer != nil }
        #endif
        return presence
    }()
    @ObservationIgnored private var readInFlight = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var channelsStale = true
    @ObservationIgnored private var writesInFlight = 0
    /// DEBUG / tests: no timers or notifications, refresh only on demand.
    @ObservationIgnored var isManual = false

    nonisolated let ioQueue = DispatchQueue(label: "DisplayControlService.io", qos: .userInitiated)

    init(hardware: DisplayHardware = SystemDisplayHardware(),
         settings: @escaping () -> DisplaysWidgetSettings = { SettingsStore[.displaysWidgetSettings] }) {
        self.hardware = hardware
        self.settingsProvider = settings
    }

    var settings: DisplaysWidgetSettings { settingsProvider() }

    func state(_ display: CGDirectDisplayID) -> DisplayControlState {
        states[display] ?? DisplayControlState()
    }

    // MARK: Lifecycle

    /// A Displays view appeared (true) or disappeared (false).
    func setVisible(_ visible: Bool) {
        presence.setVisible(visible)
    }

    /// Starts reading (idempotent) without a visible view (DEBUG hooks): it stops again at the
    /// latest one refresh interval later unless a view is visible or the widget is in the Nook.
    func start() {
        presence.touch(holdFor: TimeInterval(max(settings.refreshInterval, 5)))
    }

    /// Removes the timers and the observer now. `states` keeps the last values.
    func stop() {
        presence.forceIdle()
    }

    private func install() {
        guard !isManual, timer == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.channelsStale = true
                    self?.refresh()
                }
            }
        scheduleTimer()
        let b = Timer(timeInterval: Self.builtInPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBuiltIn() }
        }
        b.tolerance = 0.5
        RunLoop.main.add(b, forMode: .common)
        builtInTimer = b
        refresh()
    }

    /// Restarts the DDC timer with the interval from the settings.
    func reschedule() {
        guard timer != nil else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    private func scheduleTimer() {
        let t = Timer(timeInterval: TimeInterval(max(settings.refreshInterval, 5)), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.presence.debugCheckTick()
                self.refresh()
            }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        builtInTimer?.invalidate()
        builtInTimer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        refreshAgain = false
    }

    // MARK: Reading

    /// Re-enumerates the displays and reads every enabled control (DDC included).
    func refresh(completion: (@MainActor () -> Void)? = nil) {
        guard !readInFlight else {
            refreshAgain = true
            if let completion { pendingCompletions.append(completion) }
            return
        }
        if let completion { pendingCompletions.append(completion) }
        readInFlight = true
        let list = hardware.displays()
        displays = list
        let settings = self.settings
        for d in list where !d.isBuiltIn && states[d.id] == nil && settings.ddcEnabled && settings.isEnabled(d) {
            var s = DisplayControlState()
            s.ddc = .probing
            states[d.id] = s
        }
        let externalIDs = Set(list.filter { !$0.isBuiltIn }.map(\.id))
        let rebuildChannels = channelsStale || externalIDs != channelDisplayIDs || settings.ddcEnabled != channelsBuiltWithDDC
        if rebuildChannels {
            channelDisplayIDs = externalIDs
            channelsBuiltWithDDC = settings.ddcEnabled
            // a display plugged in again / after wake gets its capabilities probed again
            capabilitiesFailedAt.removeAll()
        }
        channelsStale = false
        refreshWriteGenerations = writeGeneration
        let hardware = self.hardware
        let existing = channels
        let caps = capabilitiesCache
        let now = Date()
        let skipCapabilities = Set(capabilitiesFailedAt.filter { now.timeIntervalSince($0.value) < Self.capabilitiesRetryInterval }.keys)
        ioQueue.async {
            let channels = rebuildChannels ? (settings.ddcEnabled ? hardware.ddcChannels(for: list) : [:]) : existing
            var results: [CGDirectDisplayID: DisplayControlState] = [:]
            var newCaps: [String: DDCCapabilities] = [:]
            var failedCaps: Set<String> = []
            for d in list {
                results[d.id] = Self.read(d, hardware: hardware, channel: channels[d.id],
                                          settings: settings, cachedCapabilities: caps[d.key],
                                          skipCapabilities: skipCapabilities.contains(d.key),
                                          learned: &newCaps, failed: &failedCaps)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.finishRefresh(results, channels: channels, capabilities: newCaps, failedCapabilities: failedCaps)
                }
            }
        }
    }

    @ObservationIgnored private var pendingCompletions: [@MainActor () -> Void] = []

    private func finishRefresh(_ results: [CGDirectDisplayID: DisplayControlState],
                               channels: [CGDirectDisplayID: DDCChannel],
                               capabilities: [String: DDCCapabilities], failedCapabilities: Set<String>) {
        readInFlight = false
        self.channels = channels
        capabilitiesCache.merge(capabilities) { _, new in new }
        let now = Date()
        for key in failedCapabilities { capabilitiesFailedAt[key] = now }
        for key in capabilities.keys { capabilitiesFailedAt.removeValue(forKey: key) }
        var merged: [CGDirectDisplayID: DisplayControlState] = [:]
        for (id, var s) in results {
            // keep the slider position of controls written in the last moments / still pending /
            // written while this read ran (its values were read before the write)
            if let old = states[id] {
                for c in [DisplayControl.brightness, .contrast, .volume] {
                    let key = WriteKey(display: id, control: c)
                    guard isHeld(key) || writtenDuringRefresh(key) else { continue }
                    switch c {
                    case .brightness: s.brightness = old.brightness
                    case .contrast: s.contrast = old.contrast
                    case .volume: s.volume = old.volume
                    case .input: break
                    }
                }
            }
            merged[id] = s
        }
        states = merged
        lastRefresh = Date()
        if refreshAgain {
            // a refresh was requested during this read: completions wait for the follow-up
            refreshAgain = false
            refresh()
            return
        }
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        completions.forEach { $0() }
    }

    /// Built-in brightness only (cheap; keys / auto-brightness change it).
    private func refreshBuiltIn() {
        guard let d = displays.first(where: \.isBuiltIn), settings.isEnabled(d), !readInFlight else { return }
        let key = WriteKey(display: d.id, control: .brightness)
        guard !isHeld(key) else { return }
        let hardware = self.hardware
        ioQueue.async {
            let v = hardware.builtInBrightness(d.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !self.isHeld(key), var s = self.states[d.id], let v, s.brightness != v else { return }
                    s.brightness = v
                    self.states[d.id] = s
                }
            }
        }
    }

    private func isHeld(_ key: WriteKey) -> Bool {
        if limiter.isPending(key) { return true }
        if (writesRunning[key] ?? 0) > 0 { return true }
        let now = Date()
        if let t = limiter.lastSend(key), now.timeIntervalSince(t) < Self.readHoldOff { return true }
        // counted from the write's completion: it may have waited behind a slow read on ioQueue
        if let t = writeCompletedAt[key], now.timeIntervalSince(t) < Self.readHoldOff { return true }
        return false
    }

    /// A write of `key` was flushed after the current read started.
    private func writtenDuringRefresh(_ key: WriteKey) -> Bool {
        (writeGeneration[key] ?? 0) != (refreshWriteGenerations[key] ?? 0)
    }

    /// Reads one display on the I/O queue.
    nonisolated private static func read(_ d: DisplayInfo, hardware: DisplayHardware, channel: DDCChannel?,
                                         settings: DisplaysWidgetSettings, cachedCapabilities: DDCCapabilities?,
                                         skipCapabilities: Bool = false,
                                         learned: inout [String: DDCCapabilities],
                                         failed: inout Set<String>) -> DisplayControlState {
        var s = DisplayControlState()
        s.lastRead = Date()
        guard settings.isEnabled(d) else {
            s.ddc = d.isBuiltIn ? .notApplicable : .disabled
            return s
        }
        if d.isBuiltIn {
            s.ddc = .notApplicable
            s.brightness = hardware.builtInBrightness(d.id)
            s.brightnessApproximate = hardware.builtInBrightnessIsApproximate
            s.brightnessSettable = s.brightness != nil && hardware.canSetBuiltInBrightness(d.id)
            return s
        }
        guard settings.ddcEnabled else { s.ddc = .disabled; return s }
        guard let channel else {
            s.ddc = .unavailable(hardware.supportsDDC ? "No DDC/CI connection for this display"
                                                      : "DDC/CI is not available on this Mac")
            return s
        }
        var caps = cachedCapabilities
        if caps == nil, !skipCapabilities {
            if let c = try? channel.readCapabilities() {
                caps = c
                learned[d.key] = c
            } else {
                failed.insert(d.key)   // not retried for `capabilitiesRetryInterval`
            }
        }
        s.capabilities = caps
        var anyAnswer = false
        for control in [DisplayControl.brightness, .contrast, .volume, .input] {
            if control == .volume && !settings.showVolume { continue }
            if control == .contrast && !settings.showContrast { continue }
            if control == .input && !settings.showInputSource { continue }
            // skip codes the capabilities string leaves out (except brightness, which is
            // practically universal and sometimes missing from short strings)
            if let caps, control != .brightness, !caps.supports(control.vcpCode) { continue }
            guard let reply = try? channel.readVCP(control.vcpCode) else { continue }
            anyAnswer = true
            s.maximums[control] = reply.maximum
            switch control {
            case .brightness: s.brightness = reply.fraction
            case .contrast:   s.contrast = reply.fraction
            case .volume:     s.volume = reply.fraction
            case .input:      s.inputSource = DDCInputSource.code(reply.current)
            }
        }
        s.ddc = anyAnswer ? .available : .unavailable("The display did not answer DDC/CI")
        s.brightnessSettable = s.ddc == .available && s.brightness != nil
        return s
    }

    // MARK: Writing

    /// Sets `control` of `display` to `value` (clamped to 0…1). Returns false when the control
    /// cannot be set. The write itself is coalesced and rate-limited.
    @discardableResult
    func set(_ control: DisplayControl, to value: Double, on display: CGDirectDisplayID) -> Bool {
        guard control.isSettable, value.isFinite, var s = states[display], s.isSettable(control),
              let info = displays.first(where: { $0.id == display }), settings.isEnabled(info) else { return false }
        let v = min(max(value, 0), 1)
        switch control {
        case .brightness: s.brightness = v
        case .contrast:   s.contrast = v
        case .volume:     s.volume = v
        case .input:      return false
        }
        states[display] = s
        let key = WriteKey(display: display, control: control)
        let interval = info.isBuiltIn ? Self.builtInWriteInterval : Self.ddcWriteInterval
        if let delay = limiter.submit(v, for: key, now: Date(), interval: interval) {
            if delay <= 0 {
                flush(key)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated { self.flush(key) }
                }
            }
        }
        return true
    }

    private func flush(_ key: WriteKey) {
        guard let value = limiter.flush(key: key, now: Date()),
              let info = displays.first(where: { $0.id == key.display }) else { return }
        let hardware = self.hardware
        let channel = channels[key.display]
        let maximum = states[key.display]?.maximums[key.control] ?? 100
        writesInFlight += 1
        writeGeneration[key, default: 0] += 1
        writesRunning[key, default: 0] += 1
        ioQueue.async {
            if info.isBuiltIn {
                if key.control == .brightness { _ = hardware.setBuiltInBrightness(value, display: info.id) }
            } else if let channel {
                try? channel.writeVCP(key.control.vcpCode, value: DDCPacket.value(forFraction: value, maximum: maximum))
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.writesInFlight -= 1
                    let running = (self.writesRunning[key] ?? 1) - 1
                    self.writesRunning[key] = running > 0 ? running : nil
                    self.writeCompletedAt[key] = Date()
                }
            }
        }
    }

    /// Whether writes are queued or running (tests).
    var isIdle: Bool { writesInFlight == 0 && !readInFlight && limiter.pending.isEmpty }

    /// Runs an automation command; returns the displays it changed.
    @discardableResult
    func perform(_ command: DisplayControlCommand) -> [CGDirectDisplayID] {
        displays.filter(command.matches).compactMap { d in
            guard let v = command.resolvedValue(current: state(d.id).value(command.control)),
                  set(command.control, to: v, on: d.id) else { return nil }
            return d.id
        }
    }
}
