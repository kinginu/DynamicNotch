// Batteries widget model (2026-10-20): the battery levels of this Mac and its accessories,
// like macOS Notification Center's Batteries widget. Public APIs / documented tools only:
//
//   1. this Mac        IOKit power sources (IOPSCopyPowerSourcesInfo / IOPSGetPowerSourceDescription):
//                      name, current/max capacity, is charging, power source state. Other power
//                      sources IOPS reports (UPS) are listed too.
//   2. HID accessories IOKit registry: `AppleDeviceManagementHIDEventService` and any `IOHIDDevice`
//                      with a `BatteryPercent` property (what `ioreg -r -k BatteryPercent` shows):
//                      Magic Trackpad / Mouse / Keyboard. `Product`, `Transport`, `DeviceAddress`,
//                      `VendorID` / `ProductID`, `BatteryStatusFlags`.
//   3. Bluetooth cache `/Library/Preferences/com.apple.Bluetooth.plist` ▸ `DeviceCache` ▸ <address> ▸
//                      `BatteryPercentLeft/Right/Case/Combined/Single`, `Name`, `VendorID`/`ProductID`
//                      (older macOS; absent on macOS 26, where the plist has no DeviceCache).
//   4. system_profiler `system_profiler SPBluetoothDataType -json` (documented system tool; ~0.5 s,
//                      run off the main thread): connected devices with name, address, minor type
//                      and `device_batteryLevel{Left,Right,Case,Main}` — where AirPods' levels live
//                      on macOS 26. Needs no permission (the tool runs as its own process).
//   5. Bluetooth LE    CoreBluetooth Battery Service (0x180F / Battery Level 0x2A19) of peripherals the
//                      system is already connected to (third-party BLE keyboards and mice). Only when
//                      Bluetooth access is already granted (CBManager.authorization) — the widget
//                      never triggers the permission prompt by itself; Settings has a button for it.
//      IOBluetooth     paired-device names and connect notifications, under the same condition.
//
// Devices seen by several sources are merged by Bluetooth address (and by name for LE peripherals,
// whose addresses CoreBluetooth hides). Ordering is stable: this Mac first, then by name.
// Refresh: every `refreshInterval` seconds (setting, default 30), on IOPS notifications, on
// Bluetooth connect / disconnect (IOBluetooth, when allowed) and after wake — while a Batteries
// view is visible or the widget is in the Nook (WidgetPresence). Otherwise everything is torn down:
// when the last visible view goes away or the widget is removed from the Nook.
import Foundation
import AppKit
import IOKit
import IOKit.ps
import IOBluetooth
import CoreBluetooth
import Observation

struct BatteryDevice: Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case mac, trackpad, mouse, keyboard
        case airPods, airPodsPro, airPodsMax, airPodsCase, airPodsProCase
        case headphones, gameController, ups, other

        /// SF Symbol (all verified with NSImage(systemSymbolName:) on macOS 26).
        var systemImage: String {
            switch self {
            case .mac:            return "laptopcomputer"
            case .trackpad:       return "rectangle.and.hand.point.up.left"   // no "trackpad" symbol exists
            case .mouse:          return "magicmouse"
            case .keyboard:       return "keyboard"
            case .airPods:        return "airpods"
            case .airPodsPro:     return "airpods.pro"
            case .airPodsMax:     return "airpods.max"
            case .airPodsCase:    return "airpods.chargingcase.wireless"
            case .airPodsProCase: return "airpods.pro.chargingcase.wireless"
            case .headphones:     return "headphones"
            case .gameController: return "gamecontroller"
            case .ups:            return "powerplug"
            case .other:          return "dot.radiowaves.left.and.right"
            }
        }
    }

    enum Source: String, Sendable { case powerSource, ioRegistry, bluetoothPlist, systemProfiler, bluetoothLE }

    var id: String
    var name: String
    var kind: Kind
    /// 0…100.
    var percent: Int
    var isCharging: Bool
    /// Low battery: at or below 20 % (or the device's own higher low-battery level)
    /// and not charging.
    var isLowPower: Bool
    /// On external power (this Mac / UPS). Accessories: same as `isCharging`.
    var isPluggedIn: Bool = false
    var source: Source

    var isThisMac: Bool { kind == .mac }
}

@MainActor
@Observable
final class BatteryDevicesManager: NSObject {
    static let shared = BatteryDevicesManager()

    /// All devices, this Mac first, then by name (unfiltered; the widget applies its settings).
    private(set) var devices: [BatteryDevice] = []
    private(set) var lastRefresh: Date?
    /// Which sources returned data in the last refresh (diagnostics / DEBUG log).
    private(set) var sourceSummary: [String: Int] = [:]
    /// Bluetooth (CoreBluetooth) authorization, for the settings' "Allow Bluetooth Access" row.
    private(set) var bluetoothAuthorization: CBManagerAuthorization = CBManager.authorization

    @ObservationIgnored private var started = false
    /// Monitoring runs while a Batteries view is visible or the widget is in the Nook.
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(.batteries, label: "Batteries",
                                      onNeeded: { [unowned self] in self.install() },
                                      onIdle: { [unowned self] in self.tearDown() })
        // accessories reconnect a few seconds after wake
        presence.onWake(after: 5) { [unowned self] in self.refresh() }
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in self.started || self.timer != nil }
        #endif
        return presence
    }()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var timerInterval: TimeInterval = 0
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var powerSourceLoop: CFRunLoopSource?
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotifications: [IOBluetoothUserNotification] = []
    // CoreBluetooth Battery Service
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var lePeripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var leLevels: [UUID: (name: String, percent: Int)] = [:]

    nonisolated static let batteryService = CBUUID(string: "180F")
    nonisolated static let batteryLevel = CBUUID(string: "2A19")

    /// A Batteries view appeared (true) or disappeared (false). Monitoring runs while a view is
    /// visible or the widget is in the Nook.
    func setVisible(_ visible: Bool) {
        presence.setVisible(visible)
        if visible { reschedule() }
    }

    /// Starts monitoring (idempotent) without a visible view (DEBUG hooks): it stops again at the
    /// latest one refresh interval later unless a view is visible or the widget is in the Nook.
    func start() {
        presence.touch(holdFor: refreshInterval)
        reschedule()
    }

    /// Tears down now (see `tearDown()`); the next view / Nook change starts it again.
    func stop() {
        presence.forceIdle()
    }

    private var refreshInterval: TimeInterval {
        TimeInterval(max(SettingsStore[.batteriesWidgetSettings].refreshInterval, 5))
    }

    private func install() {
        guard !started else { return }
        started = true
        reschedule()
        installPowerSourceNotification()
        if CBManager.authorization == .allowedAlways { enableBluetooth() }
        refresh()
    }

    /// Tears down the timer, the IOPS / IOBluetooth notifications and the app-level LE
    /// connections (the wake observer is the presence's). `devices` keeps the last values; the
    /// next start refreshes them.
    private func tearDown() {
        guard started else { return }
        started = false
        timer?.invalidate()
        timer = nil
        timerInterval = 0
        if let source = powerSourceLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceLoop = nil
        }
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        if let central {
            for peripheral in lePeripherals.values where peripheral.state != .disconnected {
                central.cancelPeripheralConnection(peripheral)
            }
            central.delegate = nil
        }
        central = nil
        lePeripherals.removeAll()
        leLevels.removeAll()
    }

    /// Re-arms the periodic refresh with the current `refreshInterval` setting.
    func reschedule() {
        guard started else { return }
        let interval = refreshInterval
        guard timer == nil || interval != timerInterval else { return }
        timer?.invalidate()
        timerInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.presence.debugCheckTick()
                self.refresh()
            }
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Asks for Bluetooth access (the system prompt) and, once granted, reads LE battery levels and
    /// listens for connect events.
    func requestBluetoothAccess() {
        enableBluetooth()
    }

    func openBluetoothPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        let leSnapshot = leLevels.map { LEReading(id: $0.key, name: $0.value.name, percent: $0.value.percent) }
        let pairedNames = Self.pairedDeviceNames(allowed: CBManager.authorization == .allowedAlways)
        Task.detached(priority: .utility) {
            let mac = BatterySources.powerSources()
            let hid = BatterySources.hidAccessories()
            let plist = BatterySources.bluetoothPlist()
            let profiler = BatterySources.systemProfiler()
            let merged = BatterySources.merge(mac: mac, hid: hid, plist: plist, profiler: profiler,
                                              le: leSnapshot, pairedNames: pairedNames)
            let summary = ["powerSource": mac.count, "ioRegistry": hid.count, "bluetoothPlist": plist.count,
                           "systemProfiler": profiler.count, "bluetoothLE": leSnapshot.count]
            await MainActor.run {
                let manager = BatteryDevicesManager.shared
                if manager.devices != merged { manager.devices = merged }
                manager.sourceSummary = summary
                manager.lastRefresh = Date()
                manager.bluetoothAuthorization = CBManager.authorization
                manager.refreshing = false
                if manager.refreshAgain {
                    manager.refreshAgain = false
                    manager.refresh()
                }
            }
        }
        refreshLE()
    }

    /// address (normalized) → name, from IOBluetooth's paired devices (only when Bluetooth access is
    /// granted: IOBluetooth is covered by the same privacy permission).
    private static func pairedDeviceNames(allowed: Bool) -> [String: String] {
        guard allowed, let paired = IOBluetoothDevice.pairedDevices() else { return [:] }
        var names: [String: String] = [:]
        for case let device as IOBluetoothDevice in paired {
            guard let address = device.addressString, let name = device.name, !name.isEmpty else { continue }
            names[BatterySources.normalizedAddress(address)] = name
        }
        return names
    }

    // MARK: - IOPS notifications

    private func installPowerSourceNotification() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let manager = Unmanaged<BatteryDevicesManager>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { manager.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSourceLoop = source
    }

    // MARK: - Bluetooth

    private func enableBluetooth() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        guard CBManager.authorization == .allowedAlways, connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(bluetoothDeviceConnected(_:device:)))
    }

    @objc private func bluetoothDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let n = device.register(forDisconnectNotification: self, selector: #selector(bluetoothDeviceDisconnected(_:device:))) {
            disconnectNotifications.append(n)
        }
        // battery levels show up a moment after the connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.refresh() }
    }

    @objc private func bluetoothDeviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        disconnectNotifications.removeAll { $0 === notification }
        refresh()
    }

    /// Connected LE peripherals with a Battery Service: (re)connect at app level and read 0x2A19.
    private func refreshLE() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let ids = Set(connected.map(\.identifier))
        for gone in lePeripherals.keys where !ids.contains(gone) {
            lePeripherals[gone] = nil
            leLevels[gone] = nil
        }
        for peripheral in connected {
            if lePeripherals[peripheral.identifier] == nil {
                lePeripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
            }
            if peripheral.state == .connected {
                readBattery(of: peripheral)
            } else {
                central.connect(peripheral)
            }
        }
    }

    private func readBattery(of peripheral: CBPeripheral) {
        if let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }),
           let level = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) {
            peripheral.readValue(for: level)
        } else {
            peripheral.discoverServices([Self.batteryService])
        }
    }

    fileprivate func recordLE(_ peripheral: CBPeripheral, value: Data?) {
        guard started, let byte = value?.first else { return }
        let name = peripheral.name ?? String(localized: "Bluetooth Device")
        let percent = min(Int(byte), 100)
        let changed = leLevels[peripheral.identifier]?.percent != percent
        leLevels[peripheral.identifier] = (name, percent)
        if changed { refresh() }
    }
}

// MARK: - CoreBluetooth delegates

extension BatteryDevicesManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            bluetoothAuthorization = CBManager.authorization
            if CBManager.authorization == .allowedAlways, connectNotification == nil { enableBluetooth() }
            refreshLE()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { readBattery(of: peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BatteryDevicesManager.batteryService }) else { return }
        peripheral.discoverCharacteristics([BatteryDevicesManager.batteryLevel], for: service)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let level = service.characteristics?.first(where: { $0.uuid == BatteryDevicesManager.batteryLevel }) else { return }
        peripheral.readValue(for: level)
        if level.properties.contains(.notify) { peripheral.setNotifyValue(true, for: level) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BatteryDevicesManager.batteryLevel, error == nil else { return }
        let value = characteristic.value
        MainActor.assumeIsolated { recordLE(peripheral, value: value) }
    }
}

// MARK: - Sources (pure, off the main thread)

struct LEReading: Sendable {
    var id: UUID
    var name: String
    var percent: Int
}

enum BatterySources {
    /// One battery reading of a Bluetooth / HID accessory, before merging.
    struct Reading: Sendable {
        enum Part: Sendable { case main, left, right, caseBattery, combined }
        var address: String?        // normalized "aa:bb:cc:dd:ee:ff"
        var name: String?
        var minorType: String?
        var vendorID: Int?
        var productID: Int?
        var part: Part
        var percent: Int
        var isCharging = false
        var lowLevel: Int?
        var source: BatteryDevice.Source
    }

    static let defaultLowLevel = 20

    static func normalizedAddress(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "-", with: ":")
    }

    // MARK: 1. IOKit power sources

    static func powerSources() -> [BatteryDevice] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        var result: [BatteryDevice] = []
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSIsPresentKey] as? Bool) ?? true,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int else { continue }
            let maxCapacity = max(desc[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let percent = min(max(Int((Double(current) / Double(maxCapacity) * 100).rounded()), 0), 100)
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let type = desc[kIOPSTypeKey] as? String
            let psName = desc[kIOPSNameKey] as? String ?? "Battery"
            let isInternal = type == kIOPSInternalBatteryType
            let low = (desc[kIOPSLowWarnLevelKey] as? Int) ?? defaultLowLevel
            result.append(BatteryDevice(
                id: isInternal ? "mac" : "ps:\(psName)",
                name: isInternal ? thisMacName() : psName,
                kind: isInternal ? .mac : .ups,
                percent: percent,
                isCharging: charging,
                isLowPower: !charging && !onAC && percent <= max(low, defaultLowLevel),
                isPluggedIn: onAC,
                source: .powerSource))
        }
        return result
    }

    /// "MacBook Pro" from the computer name ("Alex’s MacBook Pro"), like Notification Center.
    static func thisMacName() -> String {
        let name = Host.current().localizedName ?? ""
        let product = productName(from: name)
        if product.hasPrefix("Mac") || product.hasPrefix("iMac") { return product }
        return String(localized: "This Mac")
    }

    // MARK: 2. IOKit registry (HID accessories)

    static func hidAccessories() -> [Reading] {
        var seen = Set<String>()
        var readings: [Reading] = []
        let matches: [[String: Any]] = [
            ["IOProviderClass": "AppleDeviceManagementHIDEventService"],
            ["IOProviderClass": "IOHIDDevice", "IOPropertyExistsMatch": "BatteryPercent"],
        ]
        for match in matches {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, match as CFDictionary, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while true {
                let service = IOIteratorNext(iterator)
                if service == 0 { break }
                defer { IOObjectRelease(service) }
                var props: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let p = props?.takeRetainedValue() as? [String: Any],
                      let percent = p["BatteryPercent"] as? Int else { continue }
                let address = (p["DeviceAddress"] as? String).map(normalizedAddress)
                let product = (p["Product"] as? String)?.trimmingCharacters(in: .whitespaces)
                let key = address ?? "\(product ?? "")|\(p["SerialNumber"] as? String ?? "")|\(p["ProductID"] as? Int ?? 0)"
                guard seen.insert(key).inserted else { continue }
                // BatteryStatusFlags: non-zero while the accessory charges (bit meaning undocumented;
                // 0 when on battery on this Mac's trackpad).
                let flags = p["BatteryStatusFlags"] as? Int ?? 0
                readings.append(Reading(
                    address: address,
                    name: (product?.isEmpty ?? true) ? nil : product,
                    minorType: minorType(fromNotificationType: p["BatteryLowNotificationType"] as? String),
                    vendorID: p["VendorID"] as? Int, productID: p["ProductID"] as? Int,
                    part: .main, percent: min(max(percent, 0), 100),
                    isCharging: flags & 0x3 != 0,
                    lowLevel: p["LowBatteryNotificationPercentage"] as? Int,
                    source: .ioRegistry))
            }
        }
        return readings
    }

    /// The HID driver's notification names start with the accessory type ("TPLowBattery" = trackpad).
    private static func minorType(fromNotificationType type: String?) -> String? {
        guard let type else { return nil }
        if type.hasPrefix("TP") { return "Trackpad" }
        if type.hasPrefix("Mouse") || type.hasPrefix("MM") { return "Mouse" }
        if type.hasPrefix("KB") || type.hasPrefix("Keyboard") { return "Keyboard" }
        return nil
    }

    // MARK: 3. com.apple.Bluetooth.plist DeviceCache

    static func bluetoothPlist() -> [Reading] {
        let url = URL(fileURLWithPath: "/Library/Preferences/com.apple.Bluetooth.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let cache = plist["DeviceCache"] as? [String: [String: Any]] else { return [] }
        var readings: [Reading] = []
        for (address, entry) in cache {
            let name = entry["Name"] as? String ?? entry["DisplayName"] as? String
            let vendor = entry["VendorID"] as? Int, product = entry["ProductID"] as? Int
            let parts: [(String, Reading.Part)] = [("BatteryPercentLeft", .left), ("BatteryPercentRight", .right),
                                                   ("BatteryPercentCase", .caseBattery), ("BatteryPercentCombined", .combined),
                                                   ("BatteryPercentSingle", .main), ("BatteryPercent", .main)]
            for (key, part) in parts {
                guard let number = entry[key] as? NSNumber else { continue }
                // stored either as a 0…1 fraction (a real) or as 0…100 (an integer): only a real is
                // a fraction, so an integer 1 (a nearly empty AirPod) stays 1 %, not 100 %
                let raw = number.doubleValue
                guard raw.isFinite else { continue }
                let isFraction = CFNumberIsFloatType(number as CFNumber) && raw <= 1
                let percent = isFraction ? Int((raw * 100).rounded()) : Int(raw)
                guard percent > 0 else { continue }
                readings.append(Reading(address: normalizedAddress(address), name: name, minorType: nil,
                                        vendorID: vendor, productID: product, part: part,
                                        percent: min(percent, 100), source: .bluetoothPlist))
            }
        }
        return readings
    }

    // MARK: 4. system_profiler SPBluetoothDataType

    static func systemProfiler() -> [Reading] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        // guard against a hung tool
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var readings: [Reading] = []
        for controller in controllers {
            for wrapper in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in wrapper {
                    guard let d = value as? [String: Any] else { continue }
                    let address = (d["device_address"] as? String).map(normalizedAddress)
                    let minor = d["device_minorType"] as? String
                    let vendor = hexInt(d["device_vendorID"]), product = hexInt(d["device_productID"])
                    let parts: [(String, Reading.Part)] = [("device_batteryLevelLeft", .left), ("device_batteryLevelRight", .right),
                                                           ("device_batteryLevelCase", .caseBattery), ("device_batteryLevelMain", .main),
                                                           ("device_batteryLevel", .main)]
                    for (key, part) in parts {
                        guard let percent = percentValue(d[key]) else { continue }
                        readings.append(Reading(address: address, name: name, minorType: minor, vendorID: vendor,
                                                productID: product, part: part, percent: percent, source: .systemProfiler))
                    }
                    // connected but no level: keep the name / type for merging with the IOKit / LE readings
                    if !parts.contains(where: { d[$0.0] != nil }) {
                        readings.append(Reading(address: address, name: name, minorType: minor, vendorID: vendor,
                                                productID: product, part: .main, percent: -1, source: .systemProfiler))
                    }
                }
            }
        }
        return readings
    }

    private static func hexInt(_ value: Any?) -> Int? {
        guard let s = value as? String else { return value as? Int }
        let token = s.split(separator: " ").first.map(String.init) ?? s
        return token.hasPrefix("0x") ? Int(token.dropFirst(2), radix: 16) : Int(token)
    }

    private static func percentValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return min(max(i, 0), 100) }
        guard let s = value as? String, let i = Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { return nil }
        return min(max(i, 0), 100)
    }

    // MARK: Merge

    static func merge(mac: [BatteryDevice], hid: [Reading], plist: [Reading], profiler: [Reading],
                      le: [LEReading], pairedNames: [String: String]) -> [BatteryDevice] {
        // Per address (or per anonymous HID entry): the best value of every part. Source priority
        // for a part: IOKit registry > system_profiler > Bluetooth plist.
        struct Accessory {
            var address: String?
            var name: String?
            var minorType: String?
            var vendorID: Int?
            var productID: Int?
            var parts: [Reading.Part: Reading] = [:]
        }
        var accessories: [String: Accessory] = [:]
        var order: [String] = []
        for r in hid + profiler + plist {
            let key = r.address ?? "hid:\(r.name ?? "")|\(r.productID ?? 0)"
            if accessories[key] == nil { accessories[key] = Accessory(address: r.address); order.append(key) }
            var a = accessories[key]!
            if a.name == nil || r.source == .systemProfiler { a.name = r.name ?? a.name }
            a.minorType = a.minorType ?? r.minorType
            if r.source == .systemProfiler, let m = r.minorType { a.minorType = m }
            a.vendorID = a.vendorID ?? r.vendorID
            a.productID = a.productID ?? r.productID
            if r.percent >= 0, a.parts[r.part] == nil { a.parts[r.part] = r }
            accessories[key] = a
        }

        var devices = mac
        var leRemaining = le
        for key in order {
            guard var a = accessories[key] else { continue }
            if let address = a.address, let paired = pairedNames[address] { a.name = a.name ?? paired }
            let rawName = a.name ?? fallbackName(vendorID: a.vendorID, productID: a.productID, minorType: a.minorType)
            let name = productName(from: rawName)
            let kind = kindOf(name: rawName, minorType: a.minorType, vendorID: a.vendorID, productID: a.productID)
            let id = a.address ?? key

            if let main = a.parts[.main] ?? a.parts[.combined] {
                devices.append(device(id: id, name: name, kind: kind, reading: main))
            } else if a.parts[.left] != nil || a.parts[.right] != nil {
                // AirPods: one row for the buds (the lower of the two, as Notification Center shows)
                let buds = [a.parts[.left], a.parts[.right]].compactMap { $0 }
                let low = buds.min { $0.percent < $1.percent }!
                devices.append(device(id: id + ":buds", name: name, kind: kind, reading: low,
                                      charging: buds.contains { $0.isCharging }))
            } else if let i = leRemaining.firstIndex(where: { $0.name == rawName || productName(from: $0.name) == name }) {
                // connected device without a level in system_profiler: CoreBluetooth Battery Service
                let r = leRemaining.remove(at: i)
                devices.append(BatteryDevice(id: id, name: name, kind: kind, percent: r.percent, isCharging: false,
                                             isLowPower: r.percent <= defaultLowLevel, source: .bluetoothLE))
            }
            if let c = a.parts[.caseBattery] {
                let caseKind: BatteryDevice.Kind = (kind == .airPodsPro) ? .airPodsProCase : .airPodsCase
                devices.append(device(id: id + ":case", name: String(format: String(localized: "%@ Case"), name),
                                      kind: caseKind, reading: c))
            }
        }
        // LE peripherals not matched to a system_profiler entry
        for r in leRemaining where !devices.contains(where: { $0.name == productName(from: r.name) }) {
            devices.append(BatteryDevice(id: "le:\(r.id.uuidString)", name: productName(from: r.name),
                                         kind: kindOf(name: r.name, minorType: nil, vendorID: nil, productID: nil),
                                         percent: r.percent, isCharging: false,
                                         isLowPower: r.percent <= defaultLowLevel, source: .bluetoothLE))
        }
        return sorted(devices)
    }

    static func sorted(_ devices: [BatteryDevice]) -> [BatteryDevice] {
        devices.sorted { a, b in
            if a.isThisMac != b.isThisMac { return a.isThisMac }
            let byName = a.name.localizedStandardCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.id < b.id
        }
    }

    private static func device(id: String, name: String, kind: BatteryDevice.Kind, reading r: Reading,
                               charging: Bool? = nil) -> BatteryDevice {
        let isCharging = charging ?? r.isCharging
        return BatteryDevice(id: id, name: name, kind: kind, percent: r.percent, isCharging: isCharging,
                             isLowPower: !isCharging && r.percent <= (max(r.lowLevel ?? 0, defaultLowLevel)),
                             isPluggedIn: isCharging, source: r.source)
    }

    /// "Alex’s AirPods Pro" → "AirPods Pro" for Apple products (Notification Center shows the
    /// product name); other names are kept.
    static func productName(from name: String) -> String {
        let products = ["AirPods", "Magic Trackpad", "Magic Mouse", "Magic Keyboard", "MacBook", "Mac", "iMac", "Beats", "Powerbeats"]
        for separator in ["’s ", "'s "] {
            if let range = name.range(of: separator) {
                let rest = String(name[range.upperBound...])
                if products.contains(where: { rest.hasPrefix($0) }) { return rest }
            }
        }
        return name
    }

    private static func fallbackName(vendorID: Int?, productID: Int?, minorType: String?) -> String {
        switch kindOf(name: "", minorType: minorType, vendorID: vendorID, productID: productID) {
        case .trackpad: return "Magic Trackpad"
        case .mouse:    return vendorID == 76 ? "Magic Mouse" : String(localized: "Mouse")
        case .keyboard: return vendorID == 76 ? "Magic Keyboard" : String(localized: "Keyboard")
        default:        return String(localized: "Bluetooth Device")
        }
    }

    // Apple product IDs (vendor 0x004C) of the Magic accessories and AirPods, for entries without a
    // telling name. Best effort; names and minor types are checked first.
    private static let appleTrackpads: Set<Int> = [0x030e, 0x0265, 0x0314, 0x0324]
    private static let appleMice: Set<Int> = [0x030d, 0x0269, 0x0323]
    private static let appleKeyboards: Set<Int> = [0x0267, 0x026c, 0x029a, 0x029c, 0x029f, 0x0320, 0x0321, 0x0322]
    private static let airPodsPro: Set<Int> = [0x200e, 0x2014, 0x2024, 0x2027]
    private static let airPodsMax: Set<Int> = [0x200a, 0x201f]
    private static let airPods: Set<Int> = [0x2002, 0x200f, 0x2013, 0x2019, 0x201b]

    static func kindOf(name: String, minorType: String?, vendorID: Int?, productID: Int?) -> BatteryDevice.Kind {
        let n = name.lowercased(), m = minorType?.lowercased() ?? ""
        if n.contains("airpods max") { return .airPodsMax }
        if n.contains("airpods pro") { return .airPodsPro }
        if n.contains("airpods") { return .airPods }
        if n.contains("trackpad") || m.contains("trackpad") { return .trackpad }
        if n.contains("mouse") || m.contains("mouse") { return .mouse }
        if n.contains("keyboard") || m.contains("keyboard") { return .keyboard }
        if vendorID == 76, let pid = productID {
            if appleTrackpads.contains(pid) { return .trackpad }
            if appleMice.contains(pid) { return .mouse }
            if appleKeyboards.contains(pid) { return .keyboard }
            if airPodsPro.contains(pid) { return .airPodsPro }
            if airPodsMax.contains(pid) { return .airPodsMax }
            if airPods.contains(pid) { return .airPods }
        }
        if m.contains("headphone") || m.contains("headset") || n.contains("beats") { return .headphones }
        if m.contains("gamepad") || m.contains("joystick") || m.contains("game") || n.contains("controller") { return .gameController }
        return .other
    }
}
