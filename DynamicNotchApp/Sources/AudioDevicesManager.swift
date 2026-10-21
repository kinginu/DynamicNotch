// CoreAudio model of the Audio widget (2026-10-20): the output / input devices, the default
// output and input, the default output's volume and mute, and (optionally) the default input's
// level.
//
//   - devices: kAudioHardwarePropertyDevices (hidden devices skipped); a device is an output / input
//     when it has streams in that scope. Name, UID, transport type and (built-in outputs) the data
//     source ('hdpn' = headphones) pick the SF Symbol (AudioDevice.systemImage).
//   - defaults: kAudioHardwarePropertyDefaultOutputDevice / DefaultInputDevice, read and set on the
//     system object (the same as choosing a device in Control Center ▸ Sound).
//   - volume: the virtual main volume (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, what
//     the volume keys change), else kAudioDevicePropertyVolumeScalar on the main element, else on
//     channels 1 and 2. Mute: kAudioDevicePropertyMute. A device without a settable control (HDMI,
//     many USB DACs) shows a disabled slider.
//   - everything is kept current by property listeners (AudioObjectAddPropertyListenerBlock on the
//     main queue); the per-device volume/mute listeners move with the default output.
//   - input level: AudioInputLevelMeter (an AVAudioEngine input tap), only while a widget asks for
//     it (`meterClients`) and microphone access is usable (`microphoneStatus == .authorized`, from
//     PermissionCenter `.microphone`; a change there re-evaluates the meter).
//     Running it turns on the orange microphone indicator, so it never runs while the notch is closed.
//     It is skipped for a Bluetooth default input (`defaultInputIsBluetooth`): opening that mic
//     would drop the headset into the hands-free (call quality) profile.
import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import AVFoundation

struct AudioDevice: Identifiable, Hashable {
    enum Transport: String, Hashable {
        case builtIn, bluetooth, usb, hdmi, displayPort, thunderbolt, airPlay, virtual, aggregate, pci, other
    }

    let id: AudioObjectID
    var uid: String
    var name: String
    var transport: Transport
    var hasOutput: Bool
    var hasInput: Bool
    /// Built-in output whose current data source is the headphone jack.
    var isHeadphones: Bool = false

    /// SF Symbol for the device in the given direction.
    func systemImage(input: Bool) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("homepod mini") { return "homepodmini" }
        if n.contains("homepod") { return "homepod" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("iphone") { return "iphone" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("apple tv") { return "appletv" }
        switch transport {
        case .builtIn:
            if input { return "mic" }
            return isHeadphones || n.contains("headphone") ? "headphones" : "speaker.wave.2"
        case .bluetooth:
            if n.contains("speaker") || n.contains("soundlink") || n.contains("boom") { return input ? "mic" : "hifispeaker" }
            return "headphones"
        case .hdmi, .displayPort:
            return input ? "mic" : "display"
        case .thunderbolt, .usb, .pci:
            if n.contains("display") { return input ? "mic" : "display" }
            if n.contains("headset") || n.contains("headphone") { return "headphones" }
            return input ? "mic" : "hifispeaker"
        case .airPlay:
            return "airplayaudio"
        case .virtual, .aggregate, .other:
            return input ? "mic" : "waveform"
        }
    }
}

/// Usability of the input level meter.
enum AudioMicrophoneStatus: Equatable {
    case authorized
    case notDetermined
    case denied
    /// The app is not set up for microphone access (no `com.apple.security.device.audio-input`
    /// entitlement under the Hardened Runtime, or no NSMicrophoneUsageDescription — asking would
    /// crash the app), so the meter is never shown.
    case unavailable

    init(_ status: PermissionStatus) {
        switch status {
        case .granted:                         self = .authorized
        case .notDetermined:                   self = .notDetermined
        case .unavailable:                     self = .unavailable
        case .denied, .restricted, .limited:   self = .denied
        }
    }
}

@MainActor
@Observable
final class AudioDevicesManager {
    static let shared = AudioDevicesManager()

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioObjectID = kAudioObjectUnknown
    private(set) var defaultInputID: AudioObjectID = kAudioObjectUnknown
    /// Volume of the default output, 0…1; nil when the device has no volume control.
    private(set) var volume: Float?
    /// Mute of the default output; nil when the device has no mute control.
    private(set) var isMuted: Bool?
    /// Whether the volume can be changed (else the slider is disabled).
    private(set) var volumeSettable = false
    /// Input level of the default input, 0…1 (dBFS −60…0), while the meter runs.
    private(set) var inputLevel: Float = 0
    private(set) var isMeterRunning = false
    /// PermissionCenter `.microphone` (observable).
    var microphoneStatus: AudioMicrophoneStatus { AudioMicrophoneStatus(PermissionCenter.shared.status(for: .microphone)) }

    var outputs: [AudioDevice] { devices.filter(\.hasOutput) }
    var inputs: [AudioDevice] { devices.filter(\.hasInput) }

    /// The default input is a Bluetooth device. The meter never opens it: opening a Bluetooth
    /// headset's microphone (AirPods etc.) switches it from A2DP to the low-quality hands-free
    /// profile (mono call audio) for as long as the meter runs.
    var defaultInputIsBluetooth: Bool {
        devices.first { $0.id == defaultInputID }?.transport == .bluetooth
    }

    @ObservationIgnored private var started = false
    @ObservationIgnored private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var outputListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var listenedOutput: AudioObjectID = kAudioObjectUnknown
    @ObservationIgnored private var meter: AudioInputLevelMeter?
    @ObservationIgnored private var meterClients = 0
    @ObservationIgnored private var refreshScheduled = false
    @ObservationIgnored private var microphoneObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    /// Starts listening (idempotent). Called when the widget or its settings appear.
    func start() {
        updateMicrophoneStatus()
        guard !started else { return }
        started = true
        // access granted / revoked (prompt, System Settings): start or stop the meter
        microphoneObserver = PermissionCenter.shared.observe([.microphone]) { _, _ in
            AudioDevicesManager.shared.updateMeter()
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioCA.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            if AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main, block) == noErr {
                systemListeners.append((address, block))
            }
        }
        refresh()
    }

    /// Coalesces bursts of listener callbacks (a device change fires several properties at once).
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshScheduled = false
                self?.refresh()
            }
        }
    }

    func refresh() {
        let previousInput = defaultInputID
        devices = Self.readDevices()
        defaultOutputID = AudioCA.get(AudioObjectID(kAudioObjectSystemObject), AudioCA.address(kAudioHardwarePropertyDefaultOutputDevice), AudioObjectID(0)) ?? kAudioObjectUnknown
        defaultInputID = AudioCA.get(AudioObjectID(kAudioObjectSystemObject), AudioCA.address(kAudioHardwarePropertyDefaultInputDevice), AudioObjectID(0)) ?? kAudioObjectUnknown
        if listenedOutput != defaultOutputID { listenToOutput(defaultOutputID) }
        readVolume()
        if previousInput != defaultInputID {
            // also when the meter is not running: an input that just appeared (USB mic plugged in)
            // or a switch away from a Bluetooth input must start it
            if isMeterRunning { restartMeter() } else { updateMeter() }
        }
    }

    // MARK: - Devices

    private static func readDevices() -> [AudioDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let ids: [AudioObjectID] = AudioCA.getArray(system, AudioCA.address(kAudioHardwarePropertyDevices))
        var result: [AudioDevice] = []
        for id in ids {
            let hidden: UInt32 = AudioCA.get(id, AudioCA.address(kAudioDevicePropertyIsHidden), UInt32(0)) ?? 0
            guard hidden == 0 else { continue }
            let hasOutput = AudioCA.streamCount(id, scope: kAudioObjectPropertyScopeOutput) > 0
            let hasInput = AudioCA.streamCount(id, scope: kAudioObjectPropertyScopeInput) > 0
            guard hasOutput || hasInput else { continue }
            let name = AudioCA.getString(id, AudioCA.address(kAudioObjectPropertyName)) ?? "Audio Device"
            let uid = AudioCA.getString(id, AudioCA.address(kAudioDevicePropertyDeviceUID)) ?? "\(id)"
            let transportCode: UInt32 = AudioCA.get(id, AudioCA.address(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0
            let transport = Self.transport(transportCode)
            var headphones = false
            if hasOutput, transport == .builtIn {
                let source: UInt32? = AudioCA.get(id, AudioCA.address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput), UInt32(0))
                headphones = source == 0x6864_706E // 'hdpn'
            }
            result.append(AudioDevice(id: id, uid: uid, name: name, transport: transport,
                                      hasOutput: hasOutput, hasInput: hasInput, isHeadphones: headphones))
        }
        // built-in first, then by name (Control Center keeps the HAL order; this is stabler)
        return result.sorted { a, b in
            if (a.transport == .builtIn) != (b.transport == .builtIn) { return a.transport == .builtIn }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private static func transport(_ code: UInt32) -> AudioDevice.Transport {
        switch code {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeHDMI: return .hdmi
        case kAudioDeviceTransportTypeDisplayPort: return .displayPort
        case kAudioDeviceTransportTypeThunderbolt: return .thunderbolt
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeVirtual: return .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return .aggregate
        case kAudioDeviceTransportTypePCI: return .pci
        default: return .other
        }
    }

    /// Makes `device` the default output (or input). Returns false when CoreAudio refuses.
    @discardableResult
    func setDefault(_ device: AudioDevice, input: Bool) -> Bool {
        var address = AudioCA.address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &id)
        if status != noErr { NSLog("[Audio] set default %@ %@ failed: %d", input ? "input" : "output", device.name, status) }
        scheduleRefresh()
        return status == noErr
    }

    // MARK: - Volume / mute (default output)

    private var volumeAddresses: [AudioObjectPropertyAddress] {
        let id = defaultOutputID
        guard id != kAudioObjectUnknown else { return [] }
        var main = AudioCA.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
        if AudioObjectHasProperty(id, &main) { return [main] }
        var scalar = AudioCA.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput)
        if AudioObjectHasProperty(id, &scalar) { return [scalar] }
        return (1...2).compactMap { channel -> AudioObjectPropertyAddress? in
            var a = AudioCA.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, AudioObjectPropertyElement(channel))
            return AudioObjectHasProperty(id, &a) ? a : nil
        }
    }

    private var muteAddress: AudioObjectPropertyAddress? {
        var a = AudioCA.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        return defaultOutputID != kAudioObjectUnknown && AudioObjectHasProperty(defaultOutputID, &a) ? a : nil
    }

    private func readVolume() {
        let id = defaultOutputID
        let addresses = volumeAddresses
        let values = addresses.compactMap { AudioCA.get(id, $0, Float32(0)) }
        volume = values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
        volumeSettable = !addresses.isEmpty && addresses.allSatisfy { a in
            var a = a
            var settable: DarwinBoolean = false
            return AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
        }
        if let mute = muteAddress, let value: UInt32 = AudioCA.get(id, mute, UInt32(0)) {
            isMuted = value != 0
        } else {
            isMuted = nil
        }
    }

    func setVolume(_ value: Float) {
        let id = defaultOutputID
        var v = Float32(min(max(value, 0), 1))
        for a in volumeAddresses {
            var a = a
            AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
        volume = v
        // like the volume keys: raising the volume unmutes
        if v > 0, isMuted == true { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        guard var a = muteAddress else { return }
        var v: UInt32 = muted ? 1 : 0
        if AudioObjectSetPropertyData(defaultOutputID, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr {
            isMuted = muted
        }
    }

    private func listenToOutput(_ id: AudioObjectID) {
        for (object, address, block) in outputListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        outputListeners.removeAll()
        listenedOutput = id
        guard id != kAudioObjectUnknown else { return }
        var addresses = volumeAddresses
        if let mute = muteAddress { addresses.append(mute) }
        addresses.append(AudioCA.address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput))
        for address in addresses {
            var address = address
            guard AudioObjectHasProperty(id, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.readVolume() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main, block) == noErr {
                outputListeners.append((id, address, block))
            }
        }
    }

    // MARK: - Input level meter

    func updateMicrophoneStatus() {
        PermissionCenter.shared.refresh(.microphone)
    }

    /// Asks for microphone access (only offered when `microphoneStatus == .notDetermined`).
    func requestMicrophoneAccess() {
        guard Self.canUseMicrophone else { return }
        PermissionCenter.shared.requestAccess(.microphone) { _ in
            AudioDevicesManager.shared.updateMeter()
        }
    }

    func openMicrophonePrivacySettings() {
        PermissionCenter.shared.openSystemSettings(for: .microphone)
    }

    /// The app has the usage description and (Hardened Runtime) the audio-input entitlement.
    nonisolated static var canUseMicrophone: Bool { PermissionCenter.isConfigured(.microphone) }

    /// A visible widget wants the meter (balanced by `removeMeterClient`).
    func addMeterClient() {
        meterClients += 1
        updateMeter()
    }

    func removeMeterClient() {
        meterClients = max(meterClients - 1, 0)
        updateMeter()
    }

    func updateMeter() {
        updateMicrophoneStatus()
        let wanted = meterClients > 0 && microphoneStatus == .authorized && defaultInputID != kAudioObjectUnknown
            && !defaultInputIsBluetooth
        if wanted, meter == nil {
            let m = AudioInputLevelMeter { [weak self] level in
                MainActor.assumeIsolated { self?.inputLevel = level }
            }
            meter = m
            isMeterRunning = m.start()
            if !isMeterRunning { meter = nil }
        } else if !wanted, meter != nil {
            meter?.stop()
            meter = nil
            isMeterRunning = false
            inputLevel = 0
        }
    }

    private func restartMeter() {
        meter?.stop()
        meter = nil
        isMeterRunning = false
        updateMeter()
    }
}

/// Input level of the default input device: an AVAudioEngine tap on the input node, RMS of the
/// first channel → dBFS → 0…1 over −60…0 dB, with a fast attack / slow release. `onLevel` is
/// called on the main queue (~20 Hz).
final class AudioInputLevelMeter {
    private let engine = AVAudioEngine()
    private let onLevel: (Float) -> Void
    private var configObserver: NSObjectProtocol?

    init(onLevel: @escaping (Float) -> Void) {
        self.onLevel = onLevel
    }

    func start() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.makeTap(onLevel))
        do {
            try engine.start()
        } catch {
            NSLog("[Audio] input meter failed to start: %@", "\(error)")
            input.removeTap(onBus: 0)
            return false
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AudioDevicesManager.shared.refresh(); AudioDevicesManager.shared.restartMeterAfterConfigurationChange() }
        }
        return true
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Built outside any actor: the tap runs on the audio render thread.
    private static func makeTap(_ onLevel: @escaping (Float) -> Void) -> AVAudioNodeTapBlock {
        var smoothed: Float = 0
        return { buffer, _ in
            guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let samples = data[0]
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += samples[i] * samples[i] }
            let rms = (sum / Float(n)).squareRoot()
            let db = 20 * log10(max(rms, 1e-7))
            let level = min(max((db + 60) / 60, 0), 1)
            smoothed = level > smoothed ? level : smoothed * 0.7 + level * 0.3
            let value = smoothed
            DispatchQueue.main.async { onLevel(value) }
        }
    }
}

extension AudioDevicesManager {
    /// AVAudioEngine stops itself when the input device or its format changes.
    func restartMeterAfterConfigurationChange() {
        restartMeter()
    }
}

// MARK: - CoreAudio helpers

enum AudioCA {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func get<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }

    static func getArray<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [T] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(size) / MemoryLayout<T>.stride))
    }

    static func getString(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func streamCount(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var a = Self.address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }
}
