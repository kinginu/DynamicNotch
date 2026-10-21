// Bluetooth widget model (2026-10-20): paired devices, their connection state, connect /
// disconnect, and the Bluetooth power state. Public APIs only:
//
//   IOBluetoothDevice.pairedDevices()          paired devices: name, address, class of device,
//                                              isConnected()
//   IOBluetoothDevice.register(forConnectNotifications:) / register(forDisconnectNotification:)
//                                              refresh on connect / disconnect
//   openConnection(_:withPageTimeout:authenticationRequired:)   asynchronous connect; the result
//                                              arrives in `connectionComplete(_:status:)`
//   closeConnection()                          disconnect
//   IOBluetoothHostController.default().powerState   on / off (read only: switching Bluetooth on
//                                              or off needs private API, so the widget only shows it)
//
// IOBluetooth device access is covered by the Bluetooth privacy permission (TCC). Like the
// Batteries widget, nothing here touches IOBluetooth devices before CBManager.authorization is
// `.allowedAlways`; the widget's "Allow Bluetooth Access" button creates a CBCentralManager, which
// shows the system prompt. The power state (host controller) is readable without the permission.
// A CBCentralManager (once allowed) also reports power changes immediately; otherwise the power
// state is polled every 3 s while a Bluetooth widget is visible.
//
// Separate from BluetoothManager (the live-activity model): that one tracks only
// the most recently connected Apple device and its battery.
import Foundation
import AppKit
import IOBluetooth
import CoreBluetooth
import Observation

struct BluetoothWidgetDevice: Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case airPods, airPodsPro, airPodsMax, beats, headphones, speaker
        case keyboard, mouse, trackpad, gameController
        case phone, tablet, computer, watch, other

        /// SF Symbol (all verified with NSImage(systemSymbolName:) on macOS 26).
        var systemImage: String {
            switch self {
            case .airPods:        return "airpods"
            case .airPodsPro:     return "airpods.pro"
            case .airPodsMax:     return "airpods.max"
            case .beats:          return "beats.headphones"
            case .headphones:     return "headphones"
            case .speaker:        return "hifispeaker"
            case .keyboard:       return "keyboard"
            case .mouse:          return "magicmouse"
            case .trackpad:       return "rectangle.and.hand.point.up.left"   // no "trackpad" symbol exists
            case .gameController: return "gamecontroller"
            case .phone:          return "iphone"
            case .tablet:         return "ipad"
            case .computer:       return "laptopcomputer"
            case .watch:          return "applewatch"
            case .other:          return "dot.radiowaves.left.and.right"
            }
        }

        /// From the device name (Apple / well-known products), else the Bluetooth class of device
        /// (major class 0x01 computer, 0x02 phone, 0x04 audio/video, 0x05 peripheral, 0x07 wearable).
        static func classify(name: String?, major: UInt32, minor: UInt32) -> Kind {
            // device names often use a no-break space ("Alex’s Apple\u{00A0}Watch")
            let n = (name ?? "").lowercased().replacingOccurrences(of: "\u{00A0}", with: " ")
            if n.contains("airpods max") { return .airPodsMax }
            if n.contains("airpods pro") { return .airPodsPro }
            if n.contains("airpods") { return .airPods }
            if n.contains("beats") { return .beats }
            if n.contains("magic trackpad") || n.contains("trackpad") { return .trackpad }
            if n.contains("magic mouse") || n.contains("mouse") { return .mouse }
            if n.contains("keyboard") || n.contains("hhkb") { return .keyboard }
            if n.contains("dualsense") || n.contains("dualshock") || n.contains("xbox") || n.contains("controller")
                || n.contains("joy-con") { return .gameController }
            if n.contains("apple watch") { return .watch }
            if n.contains("iphone") { return .phone }
            if n.contains("ipad") { return .tablet }
            if n.contains("speaker") || n.contains("homepod") || n.contains("soundlink") || n.contains("sonos") { return .speaker }
            if n.contains("macbook") || n.contains("imac") || n.contains("mac mini") || n.contains("mac studio") { return .computer }
            switch major {
            case 0x01: return .computer
            case 0x02: return .phone
            case 0x04:
                switch minor {
                case 0x05, 0x07, 0x0A: return .speaker    // loudspeaker, portable audio, HiFi
                default: return .headphones               // headset, hands-free, headphones, …
                }
            case 0x05:
                if minor & 0x0F == 0x01 || minor & 0x0F == 0x02 { return .gameController }  // joystick, gamepad
                switch minor & 0x30 {
                case 0x10, 0x30: return .keyboard          // keyboard, combo
                case 0x20: return .mouse                   // pointing device
                default: return .other
                }
            case 0x07: return .watch
            default: return .other
            }
        }
    }

    /// Normalized Bluetooth address ("aa:bb:cc:dd:ee:ff").
    var id: String
    /// nil when the device has no name (only its address is known).
    var name: String?
    var kind: Kind
    var isConnected: Bool
    /// Bluetooth class of device (major, minor); 0 for most Bluetooth LE devices.
    var classMajor: UInt32 = 0
    var classMinor: UInt32 = 0

    var isUnnamed: Bool { name == nil }
    var displayName: String { name ?? id.uppercased() }

    static func normalizedAddress(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "-", with: ":")
    }
}

@MainActor
@Observable
final class BluetoothWidgetModel: NSObject {
    static let shared = BluetoothWidgetModel()

    enum PowerState: Equatable { case unknown, on, off, unavailable }
    enum Operation: Equatable { case connecting, disconnecting }
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        var message: String
    }

    /// All paired devices (unfiltered; the widget applies its settings), connected first.
    private(set) var devices: [BluetoothWidgetDevice] = []
    private(set) var power: PowerState = .unknown
    private(set) var authorization: CBManagerAuthorization = CBManager.authorization
    /// Devices with a connect / disconnect in progress (by id).
    private(set) var inFlight: [String: Operation] = [:]
    /// The last error, shown briefly at the bottom of the widget.
    private(set) var toast: Toast?
    private(set) var lastRefresh: Date?

    var isAuthorized: Bool { authorization == .allowedAlways }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    @ObservationIgnored private var powerTimer: Timer?
    /// The power poll runs while a Bluetooth view (widget / settings pane) is visible; being in the
    /// Nook alone does not count (nothing here feeds a closed-notch view).
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(nil, label: "Bluetooth",
                                      onNeeded: { [unowned self] in self.startPowerPoll() },
                                      onIdle: { [unowned self] in self.stopPowerPoll() })
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in self.powerTimer != nil }
        #endif
        return presence
    }()
    /// Connects waiting for `connectionComplete(_:status:)`, with their safety timeouts.
    @ObservationIgnored private var pendingConnects: [String: (device: IOBluetoothDevice, timeout: Timer)] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private override init() { super.init() }

    // MARK: Lifecycle (widget / settings appear and disappear)

    func start() {
        authorization = CBManager.authorization
        refreshPower()
        if isAuthorized { enableBluetooth() }
        refresh()
        presence.setVisible(true)
    }

    func stop() {
        presence.setVisible(false)
    }

    /// Same as `start()` / `stop()`.
    func setVisible(_ visible: Bool) {
        if visible { start() } else { stop() }
    }

    private func startPowerPoll() {
        guard powerTimer == nil else { return }
        powerTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated {
                let model = BluetoothWidgetModel.shared
                model.presence.debugCheckTick("power poll")
                let before = model.power
                model.authorization = CBManager.authorization
                model.refreshPower()
                if model.power != before || (model.isAuthorized && model.connectNotification == nil) {
                    if model.isAuthorized { model.enableBluetooth() }
                    model.refresh()
                }
            }
        }
    }

    private func stopPowerPoll() {
        powerTimer?.invalidate()
        powerTimer = nil
    }

    /// Shows the system Bluetooth permission prompt (creating a CBCentralManager does).
    func requestAccess() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Reading

    func refreshPower() {
        guard let controller = IOBluetoothHostController.default() else { power = .unavailable; return }
        switch controller.powerState.rawValue {
        case 1: power = .on                 // kBluetoothHCIPowerStateON
        case 0: power = .off                // kBluetoothHCIPowerStateOFF
        default: power = .unavailable       // uninitialized
        }
    }

    func refresh() {
        guard isAuthorized else { devices = []; return }
        var list: [BluetoothWidgetDevice] = []
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
            guard let address = device.addressString else { continue }
            let id = BluetoothWidgetDevice.normalizedAddress(address)
            let raw = device.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (raw?.isEmpty ?? true) || BluetoothWidgetDevice.normalizedAddress(raw ?? "") == id ? nil : raw
            let connected = device.isConnected()
            list.append(BluetoothWidgetDevice(
                id: id, name: name,
                kind: .classify(name: name, major: device.deviceClassMajor, minor: device.deviceClassMinor),
                isConnected: connected, classMajor: device.deviceClassMajor, classMinor: device.deviceClassMinor))
            if connected, disconnectNotifications[id] == nil,
               let n = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
                disconnectNotifications[id] = n
            }
        }
        list.sort { a, b in
            if a.isConnected != b.isConnected { return a.isConnected }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
        if list != devices { devices = list }
        lastRefresh = Date()
    }

    /// Battery level of a device as found by the Batteries widget (BatteryDevicesManager), if it
    /// is running. This widget does not start that manager itself.
    ///
    /// Matched by Bluetooth address (BatteryDevice.id is the normalized address, or the address +
    /// ":buds" for AirPods; ":case" is left out on purpose so the earbuds' level shows), else by
    /// product name: the Batteries manager strips the owner's possessive from Apple products
    /// ("Alex’s AirPods Pro" → "AirPods Pro"), and LE-only entries are keyed "le:<uuid>".
    func batteryPercent(for device: BluetoothWidgetDevice) -> Int? {
        let all = BatteryDevicesManager.shared.devices.filter { !$0.isThisMac }
        let byAddress = all.filter { $0.id == device.id || $0.id == device.id + ":buds" }
        if !byAddress.isEmpty { return byAddress.map(\.percent).min() }
        guard let name = device.name else { return nil }
        let product = BatterySources.productName(from: name)
        return all
            .filter { $0.name.caseInsensitiveCompare(product) == .orderedSame || $0.name.caseInsensitiveCompare(name) == .orderedSame }
            .map(\.percent)
            .min()
    }

    private func enableBluetooth() {
        guard isAuthorized else { return }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        if connectNotification == nil {
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        refresh()
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let key = disconnectNotifications.first(where: { $0.value === notification })?.key {
            disconnectNotifications[key] = nil
        }
        refresh()
    }

    // MARK: Connect / disconnect

    func toggle(_ device: BluetoothWidgetDevice) {
        guard inFlight[device.id] == nil else { return }
        if device.isConnected { disconnect(device) } else { connect(device) }
    }

    func connect(_ device: BluetoothWidgetDevice) {
        guard power == .on else { showToast(String(localized: "Bluetooth is off")); return }
        guard let bt = IOBluetoothDevice(addressString: device.id.uppercased().replacingOccurrences(of: ":", with: "-")) else {
            showToast(String(format: String(localized: "Couldn’t connect to %@"), device.displayName)); return
        }
        inFlight[device.id] = .connecting
        // page timeout in 0.625 ms slots: 0x4000 ≈ 10 s
        let result = bt.openConnection(self, withPageTimeout: 0x4000, authenticationRequired: false)
        guard result == kIOReturnSuccess else {
            inFlight[device.id] = nil
            NSLog("[Bluetooth] openConnection %@ failed: 0x%08x", device.id, result)
            showToast(String(format: String(localized: "Couldn’t connect to %@"), device.displayName))
            return
        }
        let timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
            MainActor.assumeIsolated { BluetoothWidgetModel.shared.finishConnect(device.id, status: kIOReturnTimeout) }
        }
        pendingConnects[device.id] = (bt, timeout)
    }

    /// IOBluetoothDevice's asynchronous openConnection target callback.
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard let address = device?.addressString else { return }
        finishConnect(BluetoothWidgetDevice.normalizedAddress(address), status: status)
    }

    private func finishConnect(_ id: String, status: IOReturn) {
        guard let pending = pendingConnects.removeValue(forKey: id) else { return }
        pending.timeout.invalidate()
        inFlight[id] = nil
        if status != kIOReturnSuccess {
            NSLog("[Bluetooth] connect %@ failed: 0x%08x", id, status)
            let name = devices.first { $0.id == id }?.displayName ?? id.uppercased()
            showToast(String(format: String(localized: "Couldn’t connect to %@"), name))
        }
        refresh()
    }

    func disconnect(_ device: BluetoothWidgetDevice) {
        guard let bt = IOBluetoothDevice(addressString: device.id.uppercased().replacingOccurrences(of: ":", with: "-")) else { return }
        inFlight[device.id] = .disconnecting
        Task { @MainActor in
            // let the spinner render before the (briefly blocking) IOBluetooth call
            try? await Task.sleep(nanoseconds: 50_000_000)
            let result = bt.closeConnection()
            if result != kIOReturnSuccess {
                NSLog("[Bluetooth] closeConnection %@ failed: 0x%08x", device.id, result)
                self.inFlight[device.id] = nil
                self.showToast(String(format: String(localized: "Couldn’t disconnect %@"), device.displayName))
                return
            }
            // the disconnect notification refreshes; keep the spinner until the link is down
            for _ in 0..<20 where bt.isConnected() {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            self.inFlight[device.id] = nil
            if bt.isConnected() {
                self.showToast(String(format: String(localized: "Couldn’t disconnect %@"), device.displayName))
            }
            self.refresh()
        }
    }

    func showToast(_ message: String) {
        toast = Toast(message: message)
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self.toast = nil
        }
    }

    #if DEBUG
    /// DEBUG (btstate): one-line summary for the log.
    var debugSummary: String {
        "auth=\(authorization.rawValue) power=\(power) devices=\(devices.count) connected=\(devices.filter(\.isConnected).count) inFlight=\(inFlight.count) viewers=\(presence.visibleCount)"
    }
    #endif
}

extension BluetoothWidgetModel: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            authorization = CBManager.authorization
            switch central.state {
            case .poweredOn: power = .on
            case .poweredOff: power = .off
            case .unsupported: power = .unavailable
            default: refreshPower()
            }
            if isAuthorized { enableBluetooth() }
            refresh()
        }
    }
}
