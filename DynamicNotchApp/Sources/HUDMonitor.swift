// F5 (2026-10-20): volume / display-brightness / keyboard-backlight HUD in the closed notch
// (`LiveActivity.hud`, HUDLiveActivityView). Findings and limits on Mac14,9 / macOS 26: docs/hud.md.
//
// Detection (public API only, no private frameworks):
//   - media keys (NX_SYSDEFINED, subtype 8 = aux control buttons: sound up/down/mute, brightness
//     up/down, illumination up/down/toggle):
//       * Input Monitoring granted (PermissionCenter `.inputMonitoring`) → a listen-only CGEvent tap on the
//         main run loop (it never modifies or swallows events);
//       * otherwise → `NSEvent.addGlobalMonitorForEvents(matching: .systemDefined)` (no prompt;
//         whether macOS delivers media keys to it without permission is reported in Settings
//         once a key arrives).
//     The app never asks for Input Monitoring on its own; the HUD pane has the permission row.
//   - volume: CoreAudio property listeners on the default output device (virtual main volume, else
//     the volume scalar on the main element / channels 1–2, and mute). Works without permission and
//     also catches changes from Control Center or other apps. Device switches re-baseline silently.
//   - display brightness: no public API reports it on Apple Silicon. IODisplayGetFloatParameter
//     returns kIOReturnUnsupported for every service, and the IORegistry value of AppleARMBacklight
//     (`IODisplayParameters.brightness`) does not track the user brightness (docs/hud.md). The level
//     is read from `/usr/libexec/corebrightnessdiag status-info` (an Apple diagnostic tool that prints
//     CoreBrightness' state as a plist; run as a subprocess, off the main thread, only after a
//     brightness / illumination key). If that fails, the HUD shows the direction only.
//   - keyboard backlight: the level is not readable through IOKit (a vendor-page HID user device);
//     the same corebrightnessdiag read gives `KeyboardBacklightBrightness`. Triggered by the
//     illumination keys only (Mac14,9's built-in keyboard has none: it is set from Control Center).
//
// The system's own HUD is not hidden: there is no public, safe way (docs/hud.md).
//
// Presentation: every trigger updates `reading` and (re)arms a 1.2 s hide timer, so key repeats and
// the CoreAudio notifications that follow a key press coalesce into one HUD whose bar animates.
import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import IOKit
import IOKit.graphics
import IOKit.hid
import CoreGraphics
import ApplicationServices
import Observation

@MainActor
@Observable
final class HUDMonitor {
    static let shared = HUDMonitor()

    enum Kind: String, CaseIterable, Codable, Equatable {
        case volume, brightness, keyboardBacklight
    }

    enum Direction: Equatable { case up, down, toggle }

    /// What the HUD shows.
    struct Reading: Equatable {
        var kind: Kind
        /// 0…1; nil = unknown (no readable level).
        var level: Double?
        var muted: Bool = false
        /// Last key direction (used when the level is unknown).
        var direction: Direction? = nil
    }

    enum KeySource: Equatable {
        case off
        case eventTap
        case globalMonitor
        case unavailable
    }

    /// The reading on screen (kept for the hide transition after the activity is removed).
    private(set) var reading: Reading?
    /// Whether `.hud` is currently requested.
    private(set) var isShowing = false

    private(set) var keySource: KeySource = .off
    private(set) var inputMonitoringGranted = false
    /// Media-key events received since launch (diagnostics; tells whether the global monitor works).
    private(set) var mediaKeyEventsSeen = 0
    /// Any NX_SYSDEFINED event received since launch (diagnostics).
    private(set) var systemDefinedEventsSeen = 0
    /// Name of the default output device (nil = none / volume HUD off).
    private(set) var outputDeviceName: String?
    /// Whether the last corebrightnessdiag read succeeded (nil = not tried yet).
    private(set) var coreBrightnessReadable: Bool?

    static let hideDelay: TimeInterval = 1.2
    /// macOS brightness key step (1/16; ⌥⇧ gives 1/64), used to predict the level until the read lands.
    static let brightnessStep = 1.0 / 16
    static let fineBrightnessStep = 1.0 / 64

    @ObservationIgnored private var started = false
    @ObservationIgnored private var settings = SettingsStore[.hudSettings]
    @ObservationIgnored private var masterEnabled = SettingsStore[.liveActivitiesSettings].enableVolumeBrightness
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var hideItem: DispatchWorkItem?
    @ObservationIgnored private var clearItem: DispatchWorkItem?
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var tapSource: CFRunLoopSource?
    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var volume = HUDVolumeObserver()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Value-observer changes before this date only re-baseline (launch, wake).
    @ObservationIgnored private var quietUntil = Date.distantPast
    @ObservationIgnored private var lastLevels: [Kind: Double] = [:]
    @ObservationIgnored private var levelRead = HUDLevelReadScheduler()

    private init() {}

    // MARK: lifecycle

    /// Called once at launch (LiveActivitiesStartup).
    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        HUDDebugHooks.install()
        #endif
        quietUntil = Date().addingTimeInterval(1.5)
        // Callbacks first: refreshPermissions() can reconfigure() (Input Monitoring already granted)
        // and so start the volume observer, whose start() delivers the baseline reading that seeds
        // lastLevels[.volume]. Without onChange that reading was lost, and a later re-notify of the
        // same level counted as a change (spurious volume HUD).
        volume.onChange = { [weak self] level, muted, deviceChanged in
            self?.volumeChanged(level: level, muted: muted, deviceChanged: deviceChanged)
        }
        levelRead.onResult = { [weak self] snapshot in
            self?.applyCoreBrightness(snapshot)
        }
        refreshPermissions()

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    HUDMonitor.shared.quietUntil = Date().addingTimeInterval(3)
                    HUDMonitor.shared.reenableTap()
                }
            })
        }
        // PermissionCenter refreshes on app activation and while its rows are on screen
        observers.append(PermissionCenter.shared.observe([.inputMonitoring]) { _, _ in
            HUDMonitor.shared.refreshPermissions()
        })

        tasks.append(Task { @MainActor [weak self] in
            for await value in SettingsStore.updates(.hudSettings, initial: false) {
                guard let self else { return }
                if value != self.settings { self.settings = value; self.reconfigure() }
            }
        })
        tasks.append(Task { @MainActor [weak self] in
            for await value in SettingsStore.updates(.liveActivitiesSettings, initial: false) {
                guard let self else { return }
                if value.enableVolumeBrightness != self.masterEnabled {
                    self.masterEnabled = value.enableVolumeBrightness
                    self.reconfigure()
                }
            }
        })
        reconfigure()
        // seed the brightness / keyboard levels so the first key press shows a level at once
        if keySource != .off, enabled(.brightness) || enabled(.keyboardBacklight) { levelRead.request() }
    }

    private func enabled(_ kind: Kind) -> Bool { masterEnabled && settings.shows(kind) }

    /// Starts / stops the key source and the volume observer to match the settings.
    func reconfigure() {
        // volume observer
        if enabled(.volume) {
            if !volume.isRunning {
                volume.start()
                quietUntil = max(quietUntil, Date().addingTimeInterval(0.5))
            }
        } else {
            volume.stop()
        }
        outputDeviceName = volume.isRunning ? volume.deviceName : nil

        // key source
        let wantKeys = masterEnabled && settings.useMediaKeys && Kind.allCases.contains(where: enabled)
        let wanted: KeySource = !wantKeys ? .off : (inputMonitoringGranted ? .eventTap : .globalMonitor)
        if wanted != keySource || (wanted == .eventTap && tap == nil)
            || (wanted == .globalMonitor && (globalMonitor == nil || localMonitor == nil)) {
            stopKeySource()
            switch wanted {
            case .eventTap:
                keySource = startTap() ? .eventTap : (startGlobalMonitor() ? .globalMonitor : .unavailable)
            case .globalMonitor:
                keySource = startGlobalMonitor() ? .globalMonitor : .unavailable
            default:
                keySource = .off
            }
        }

        // a kind that was switched off while shown
        if let r = reading, isShowing, !enabled(r.kind) { hide() }
    }

    // MARK: permissions

    /// Re-reads Input Monitoring (PermissionCenter `.inputMonitoring`) and switches the key source
    /// when it changed.
    func refreshPermissions() {
        let granted = PermissionCenter.shared.refresh(.inputMonitoring).isGranted
        if granted != inputMonitoringGranted {
            inputMonitoringGranted = granted
            if started { reconfigure() }
        }
    }

    /// Input Monitoring status for PermissionCenter. IOHIDCheckAccess reports "denied" (not
    /// "unknown") for an app that was never asked (seen on macOS 26), so like Screen Recording /
    /// Accessibility the first request is remembered and the status stays `.notDetermined` until
    /// then: the row offers the system prompt first and System Settings after.
    nonisolated static func listenEventStatus() -> PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied:
            return UserDefaults.standard.bool(forKey: listenEventPromptedKey) ? .denied : .notDetermined
        default: return .notDetermined
        }
    }

    nonisolated static let listenEventPromptedKey = "permissionPrompted.inputMonitoring"

    /// PermissionCenter's request: the system prompt (adds the app to System Settings ▸ Input
    /// Monitoring); remembered so the next request opens System Settings instead.
    nonisolated static func requestListenEventAccess() {
        UserDefaults.standard.set(true, forKey: listenEventPromptedKey)
        _ = CGRequestListenEventAccess()
    }

    // MARK: key sources

    private func startTap() -> Bool {
        let mask = CGEventMask(1) << 14 // NX_SYSDEFINED
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                           options: .listenOnly, eventsOfInterest: mask,
                                           callback: HUDMonitor.tapCallback, userInfo: nil) else {
            NSLog("[HUD] listen-only event tap could not be created")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
        return true
    }

    /// Listen-only tap callback (main run loop). The event is always passed through unchanged.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated { HUDMonitor.shared.reenableTap() }
        } else if type.rawValue == 14, let ns = NSEvent(cgEvent: event) {
            MainActor.assumeIsolated { HUDMonitor.shared.handleSystemDefined(ns) }
        }
        return Unmanaged.passUnretained(event)
    }

    fileprivate func reenableTap() {
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Without Input Monitoring: a global monitor (events for other apps) plus a local one, since a
    /// global monitor never sees events delivered to DynamicNotch itself (e.g. brightness keys
    /// pressed while Settings ▸ HUD is frontmost). The local monitor passes the event on unchanged.
    private func startGlobalMonitor() -> Bool {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { event in
            MainActor.assumeIsolated { HUDMonitor.shared.handleSystemDefined(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            MainActor.assumeIsolated { HUDMonitor.shared.handleSystemDefined(event) }
            return event
        }
        return globalMonitor != nil
    }

    private func stopKeySource() {
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        tapSource = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        keySource = .off
    }

    /// NX_SYSDEFINED: subtype 8 carries the aux control buttons; data1 = key type << 16 | flags,
    /// flags >> 8 = 0x0A (down) / 0x0B (up), bit 0 = repeat.
    func handleSystemDefined(_ event: NSEvent) {
        systemDefinedEventsSeen += 1
        guard event.subtype.rawValue == 8 else { return }
        let data1 = event.data1
        let keyType = Int32((data1 & 0xFFFF_0000) >> 16)
        let state = (data1 & 0xFF00) >> 8
        guard state == 0x0A else { return } // key down (incl. auto-repeat)
        let fine = event.modifierFlags.contains([.option, .shift])
        handleMediaKey(keyType, fine: fine)
    }

    /// `keyType`: NX_KEYTYPE_* (ev_keymap.h).
    func handleMediaKey(_ keyType: Int32, fine: Bool = false) {
        switch keyType {
        case 0, 1, 7: // SOUND_UP, SOUND_DOWN, MUTE
            mediaKeyEventsSeen += 1
            guard enabled(.volume) else { return }
            let now = volume.read()
            show(Reading(kind: .volume, level: now.level, muted: now.muted,
                         direction: keyType == 0 ? .up : (keyType == 1 ? .down : .toggle)))
        case 2, 3: // BRIGHTNESS_UP, BRIGHTNESS_DOWN
            mediaKeyEventsSeen += 1
            guard enabled(.brightness) else { return }
            stepped(.brightness, up: keyType == 2, fine: fine)
        case 21, 22, 23: // ILLUMINATION_UP, _DOWN, _TOGGLE
            mediaKeyEventsSeen += 1
            guard enabled(.keyboardBacklight) else { return }
            if keyType == 23 {
                show(Reading(kind: .keyboardBacklight, level: nil, direction: .toggle))
                levelRead.request()
            } else {
                stepped(.keyboardBacklight, up: keyType == 21, fine: fine)
            }
        default:
            break
        }
    }

    /// Brightness-like keys: predict the level from the last known one, then correct it with a
    /// (debounced, single in-flight) corebrightnessdiag read.
    private func stepped(_ kind: Kind, up: Bool, fine: Bool) {
        let base = (reading?.kind == kind ? reading?.level : nil) ?? lastLevels[kind]
        let step = fine ? Self.fineBrightnessStep : Self.brightnessStep
        let predicted = base.map { min(1, max(0, (($0 / step).rounded() + (up ? 1 : -1)) * step)) }
        show(Reading(kind: kind, level: predicted, direction: up ? .up : .down))
        levelRead.request()
    }

    private func applyCoreBrightness(_ snapshot: HUDCoreBrightness.Snapshot?) {
        coreBrightnessReadable = snapshot != nil
        guard let snapshot else { return }
        if let d = snapshot.displayBrightness { lastLevels[.brightness] = d }
        if let k = snapshot.keyboardBrightness { lastLevels[.keyboardBacklight] = k }
        guard isShowing, var r = reading else { return }
        switch r.kind {
        case .brightness: if let d = snapshot.displayBrightness { r.level = d }
        case .keyboardBacklight: if let k = snapshot.keyboardBrightness { r.level = k }
        case .volume: return
        }
        if r != reading { reading = r }
    }

    // MARK: value observers

    private func volumeChanged(level: Double?, muted: Bool, deviceChanged: Bool) {
        outputDeviceName = volume.deviceName
        let last = lastLevels[.volume]
        lastLevels[.volume] = level
        let lastMuted = volume.lastMuted
        volume.lastMuted = muted
        guard enabled(.volume), !deviceChanged, Date() >= quietUntil else { return }
        let levelMoved: Bool
        switch (level, last) {
        case let (l?, p?): levelMoved = abs(l - p) > 0.0005
        case (nil, nil): levelMoved = false
        default: levelMoved = true
        }
        guard levelMoved || muted != lastMuted else { return }
        let direction: Direction? = muted != lastMuted ? .toggle : ((level ?? 0) > (last ?? 0) ? .up : .down)
        show(Reading(kind: .volume, level: level, muted: muted, direction: direction))
    }

    // MARK: presentation

    func show(_ new: Reading) {
        clearItem?.cancel()
        clearItem = nil
        if new.level != nil { lastLevels[new.kind] = new.level }
        if new != reading { reading = new }
        if !isShowing {
            isShowing = true
            ActiveLiveActivitiesManager.shared.insertSync(.hud)
        }
        hideItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        hideItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: item)
    }

    func hide() {
        hideItem?.cancel()
        hideItem = nil
        guard isShowing else { return }
        isShowing = false
        ActiveLiveActivitiesManager.shared.removeSync(.hud)
        // keep the reading during the removal transition, then drop it
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isShowing else { return }
            self.reading = nil
        }
        clearItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    // MARK: Settings strings

    var keySourceDescription: String {
        switch keySource {
        case .off: return "Off"
        case .eventTap: return mediaKeyEventsSeen > 0 ? "Event tap (listen-only), working" : "Event tap (listen-only)"
        case .globalMonitor: return mediaKeyEventsSeen > 0 ? "Global event monitor, working" : "Global event monitor (no key seen yet)"
        case .unavailable: return "Unavailable"
        }
    }

    var volumeSourceDescription: String {
        guard enabled(.volume) else { return "Off" }
        return outputDeviceName.map { "CoreAudio: \($0)" } ?? "No output device"
    }

    var brightnessSourceDescription: String {
        guard enabled(.brightness) else { return "Off" }
        let keys = keySource == .eventTap || (keySource == .globalMonitor && mediaKeyEventsSeen > 0)
        let level: String
        switch coreBrightnessReadable {
        case .some(true): level = "level from corebrightnessdiag"
        case .some(false): level = "level unknown"
        case .none: level = "level read on first key"
        }
        return keys ? "Keys, \(level)" : (keySource == .globalMonitor ? "Keys if delivered, \(level)" : "Needs the keys")
    }

    var keyboardSourceDescription: String {
        guard enabled(.keyboardBacklight) else { return "Off" }
        guard keySource != .off, keySource != .unavailable else { return "Needs the keys" }
        return coreBrightnessReadable == false ? "Illumination keys, level unknown" : "Illumination keys, level from corebrightnessdiag"
    }

    #if DEBUG
    var debugDescription: String {
        "keySource=\(keySource) inputMonitoring=\(inputMonitoringGranted) ax=\(AXIsProcessTrusted()) sysdefSeen=\(systemDefinedEventsSeen) mediaKeysSeen=\(mediaKeyEventsSeen) master=\(masterEnabled) settings=\(settings) volume=\(volume.isRunning ? "\(volume.deviceName ?? "?") \(volume.read())" : "off") coreBrightness=\(String(describing: coreBrightnessReadable)) last=\(lastLevels) showing=\(isShowing) reading=\(String(describing: reading))"
    }
    #endif
}

// MARK: - Volume (CoreAudio)

/// Default-output volume and mute via property listeners (main queue). Calls `onChange` once per
/// main-queue turn however many channel / property notifications arrive.
@MainActor
final class HUDVolumeObserver {
    var onChange: ((Double?, Bool, Bool) -> Void)?
    var lastMuted = false
    private(set) var isRunning = false
    private(set) var deviceName: String?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var pending = false
    private var pendingDeviceChange = false

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        var a = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.schedule(deviceChanged: true) }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main, block) == noErr {
            systemListener = block
        }
        bind(to: Self.defaultOutput())
        let now = read()
        lastMuted = now.muted
        onChange?(now.level, now.muted, true)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        unbind()
        if let block = systemListener {
            var a = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main, block)
        }
        systemListener = nil
        deviceName = nil
    }

    private func schedule(deviceChanged: Bool) {
        pendingDeviceChange = pendingDeviceChange || deviceChanged
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                let changed = self.pendingDeviceChange
                self.pending = false
                self.pendingDeviceChange = false
                if changed { self.bind(to: Self.defaultOutput()) }
                let now = self.read()
                self.onChange?(now.level, now.muted, changed)
            }
        }
    }

    private static func defaultOutput() -> AudioObjectID {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return status == noErr ? id : AudioObjectID(kAudioObjectUnknown)
    }

    /// The addresses that carry the output volume: the virtual main volume (what the keys change),
    /// else the scalar on the main element, else channels 1 and 2.
    private func volumeAddresses(_ id: AudioObjectID) -> [AudioObjectPropertyAddress] {
        guard id != kAudioObjectUnknown else { return [] }
        var main = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
        if AudioObjectHasProperty(id, &main) { return [main] }
        var scalar = Self.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput)
        if AudioObjectHasProperty(id, &scalar) { return [scalar] }
        return (1...2).compactMap { channel in
            var a = Self.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, AudioObjectPropertyElement(channel))
            return AudioObjectHasProperty(id, &a) ? a : nil
        }
    }

    private func bind(to id: AudioObjectID) {
        unbind()
        device = id
        deviceName = Self.name(of: id)
        guard id != kAudioObjectUnknown else { return }
        var addresses = volumeAddresses(id)
        // also the per-channel scalars: some drivers only notify those
        for channel in [kAudioObjectPropertyElementMain, 1, 2] {
            let a = Self.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, channel)
            if !addresses.contains(where: { $0.mSelector == a.mSelector && $0.mElement == a.mElement }) { addresses.append(a) }
        }
        addresses.append(Self.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput))
        for address in addresses {
            var a = address
            guard AudioObjectHasProperty(id, &a) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.schedule(deviceChanged: false) }
            }
            if AudioObjectAddPropertyListenerBlock(id, &a, DispatchQueue.main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func unbind() {
        for (address, block) in deviceListeners {
            var a = address
            AudioObjectRemovePropertyListenerBlock(device, &a, DispatchQueue.main, block)
        }
        deviceListeners.removeAll()
        device = AudioObjectID(kAudioObjectUnknown)
    }

    /// Current volume (nil = the device has no volume control) and mute.
    func read() -> (level: Double?, muted: Bool) {
        let id = device
        guard id != kAudioObjectUnknown else { return (nil, false) }
        let values: [Double] = volumeAddresses(id).compactMap { address in
            var a = address
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr ? Double(v) : nil
        }
        var m = Self.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let hasMute = AudioObjectHasProperty(id, &m) && AudioObjectGetPropertyData(id, &m, 0, nil, &size, &muted) == noErr
        return (values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), hasMute && muted != 0)
    }

    private static func name(of id: AudioObjectID) -> String? {
        guard id != kAudioObjectUnknown else { return nil }
        var a = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

// MARK: - Brightness / keyboard backlight levels

/// Readers for the display-brightness and keyboard-backlight levels (findings: docs/hud.md).
enum HUDCoreBrightness {
    struct Snapshot: Equatable {
        /// Built-in display, user brightness 0…1 (`DisplayServicesBrightness`).
        var displayBrightness: Double?
        /// Built-in keyboard backlight 0…1 (`KeyboardBacklightBrightness`).
        var keyboardBrightness: Double?
    }

    static let toolPath = "/usr/libexec/corebrightnessdiag"

    /// Runs `corebrightnessdiag status-info` (plist on stdout) and picks the built-in display's and
    /// keyboard's levels. Blocking (≈ 0.1–0.3 s); call off the main thread. nil = tool missing,
    /// failed, timed out (2 s) or the output had neither value.
    nonisolated static func read() -> Snapshot? {
        guard FileManager.default.isExecutableFile(atPath: toolPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["status-info"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timeout)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }

    nonisolated static func parse(_ data: Data) -> Snapshot? {
        // skip anything printed before the plist
        let start = data.range(of: Data("<?xml".utf8))?.lowerBound ?? data.startIndex
        guard let root = try? PropertyListSerialization.propertyList(from: data[start...], options: [], format: nil) as? [String: Any]
        else { return nil }
        var snapshot = Snapshot()
        if let displays = root["CBDisplays"] as? [String: Any] {
            for case let entry as [String: Any] in displays.values {
                guard let d = entry["Display"] as? [String: Any] else { continue }
                if (d["DisplayServicesIsBuiltInDisplay"] as? Bool) == true,
                   let v = (d["DisplayServicesBrightness"] as? NSNumber)?.doubleValue {
                    snapshot.displayBrightness = min(1, max(0, v))
                }
            }
        }
        if let keyboards = root["CBKeyboards"] as? [String: Any] {
            for case let entry as [String: Any] in keyboards.values {
                guard let k = entry["CBKeyboardBacklightContainer"] as? [String: Any] else { continue }
                if (k["KeyboardBacklightBuiltIn"] as? Bool) ?? true,
                   let v = (k["KeyboardBacklightBrightness"] as? NSNumber)?.doubleValue {
                    snapshot.keyboardBrightness = min(1, max(0, v))
                }
            }
        }
        return snapshot.displayBrightness == nil && snapshot.keyboardBrightness == nil ? nil : snapshot
    }

    /// Public IOKit path (Intel / legacy displays): IODisplayGetFloatParameter(kIODisplayBrightnessKey)
    /// on the IODisplayConnect services. Returns kIOReturnUnsupported (or finds no service) on Apple
    /// Silicon; kept for the record and the DEBUG `hudstate` probe.
    nonisolated static func ioDisplayBrightness() -> (value: Double?, result: kern_return_t) {
        var result: kern_return_t = KERN_FAILURE
        for cls in ["IODisplayConnect", "AppleARMBacklight"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                var value: Float = 0
                result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
                if result == KERN_SUCCESS { return (Double(value), result) }
            }
        }
        return (nil, result)
    }

    /// IORegistry `AppleARMBacklight` → `IODisplayParameters` (brightness / rawBrightness /
    /// BrightnessMilliNits as value/min/max). Diagnostics only: on Mac14,9 / macOS 26 it does not
    /// follow the user brightness (docs/hud.md).
    nonisolated static func armBacklightParameters() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IODisplayParameters" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }
}

/// Debounced, single-in-flight corebrightnessdiag reads: a request waits 150 ms (the brightness
/// ramp), and requests made while a read runs cause exactly one more read afterwards.
///
/// Only a missing tool turns reads off for good. Any other failure (the 2 s timeout, a non-zero
/// exit, a plist without the built-in values — e.g. a slow read during login) starts a cooldown
/// of `failureBackoff`: requests in it are skipped (the HUD shows the direction only), and the
/// first request after it tries again.
@MainActor
final class HUDLevelReadScheduler {
    var onResult: ((HUDCoreBrightness.Snapshot?) -> Void)?
    /// Cooldown after a failed read.
    var failureBackoff: TimeInterval = 30
    var debounceInterval: TimeInterval = 0.15
    private let reader: @Sendable () -> HUDCoreBrightness.Snapshot?
    private let toolAvailable: () -> Bool
    private let now: () -> Date
    private var running = false
    private var again = false
    private var debounce: DispatchWorkItem?
    /// The tool is missing: requests are skipped for the rest of the session.
    private(set) var toolMissing = false
    /// After a failed read: requests before this date are skipped.
    private(set) var cooldownUntil: Date?
    /// Failed reads in a row (reset by a successful one).
    private(set) var consecutiveFailures = 0

    init(reader: @escaping @Sendable () -> HUDCoreBrightness.Snapshot? = { HUDCoreBrightness.read() },
         toolAvailable: @escaping () -> Bool = { FileManager.default.isExecutableFile(atPath: HUDCoreBrightness.toolPath) },
         now: @escaping () -> Date = Date.init) {
        self.reader = reader
        self.toolAvailable = toolAvailable
        self.now = now
    }

    /// False while the tool is missing or a failure cooldown runs.
    var acceptsRequests: Bool {
        guard !toolMissing else { return false }
        if let cooldownUntil, now() < cooldownUntil { return false }
        return true
    }

    func request() {
        guard !toolMissing else { return }
        guard toolAvailable() else { toolMissing = true; onResult?(nil); return }
        guard acceptsRequests else { return }
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.run() }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func run() {
        guard !running else { again = true; return }
        running = true
        let reader = reader
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = reader()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finish(snapshot) }
            }
        }
    }

    private func finish(_ snapshot: HUDCoreBrightness.Snapshot?) {
        running = false
        if snapshot == nil {
            consecutiveFailures += 1
            cooldownUntil = now().addingTimeInterval(failureBackoff)
            again = false   // the cooldown also drops a read queued behind the failed one
        } else {
            consecutiveFailures = 0
            cooldownUntil = nil
        }
        onResult?(snapshot)
        if again {
            again = false
            run()
        }
    }
}
