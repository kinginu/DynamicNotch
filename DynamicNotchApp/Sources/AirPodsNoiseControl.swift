// F7 (2026-10-21): AirPods listening mode (Off / Transparency / Adaptive / Noise Cancellation)
// from the Audio widget. docs/airpods.md has the design and what was verified on this Mac.
//
// There is no public API for the listening mode. The only public route is the one a person uses:
// Control Center's Sound menu (menu extra `com.apple.menuextra.sound`) lists the output devices,
// and the selected AirPods row shows one checkbox per listening mode. AirPodsControlCenterDriver
// opens that menu through the Accessibility API (AXUIElement), reads / presses the checkbox and
// closes the menu again. The private AAP Bluetooth protocol (what some tools use to switch modes
// without UI) is deliberately not used.
//
//   - AirPodsListeningMode: the four modes, their Control Center labels and SF Symbols.
//   - AirPodsModel: which AirPods have listening modes (Bluetooth product id, else the name).
//   - ControlCenterSoundMenuParser: pure parser of a flattened snapshot of the Sound menu's AX tree
//     (unit-tested without Control Center: Tests/AirPodsNoiseControlTests).
//   - AirPodsNoiseControlService: @MainActor model the views use. Detection of the current output,
//     a per-device cache of the last mode read, one operation at a time, a minimum interval
//     between menu openings, and coalescing of rapid clicks (the latest wins).
import Foundation
import AppKit
import ApplicationServices
import Observation

// MARK: - Modes

enum AirPodsListeningMode: String, CaseIterable, Codable, Hashable, Sendable {
    case off, transparency, adaptive, noiseCancellation

    /// Name shown in the UI (the same words Control Center uses).
    var title: String {
        switch self {
        case .off: return String(localized: "Off")
        case .transparency: return String(localized: "Transparency")
        case .adaptive: return String(localized: "Adaptive")
        case .noiseCancellation: return String(localized: "Noise Cancellation")
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "circle.slash"
        case .transparency: return "ear"
        case .adaptive: return "sparkles"
        case .noiseCancellation: return "waveform.slash"
        }
    }

    /// Checkbox labels in Control Center's Sound menu, per mode (AXTitle or AXDescription,
    /// compared case-insensitively). English is the label seen on macOS 26 (and in the
    /// open-source scripts that drive this menu); the Japanese ones are unverified guesses for
    /// the user's secondary language.
    var controlCenterLabels: [String] {
        switch self {
        case .off: return ["Off", "オフ"]
        case .transparency: return ["Transparency", "外部音取り込み"]
        case .adaptive: return ["Adaptive", "適応型"]
        case .noiseCancellation: return ["Noise Cancellation", "ノイズキャンセリング"]
        }
    }

    init?(controlCenterLabel label: String) {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mode = Self.allCases.first(where: { m in
            m.controlCenterLabels.contains { $0.compare(l, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }
        }) else { return nil }
        self = mode
    }
}

// MARK: - Models

/// AirPods with listening modes. Product ids are Apple's Bluetooth product ids (vendor 0x004C) as
/// `system_profiler SPBluetoothDataType` reports them; 0x2024 (AirPods Pro 2, USB-C) is verified on
/// this Mac, the others are community-sourced (docs/airpods.md).
enum AirPodsModel: String, Hashable, Sendable {
    case airPodsPro, airPodsPro2, airPodsPro3, airPodsMax, airPods4ANC
    /// The name says AirPods Pro / Max but the product id is unknown: assume all modes and let
    /// the Sound menu tell which exist.
    case unknownWithListeningModes

    static let appleVendorID = 0x004C

    /// nil: not AirPods with listening modes (AirPods 1–4 without ANC, Beats, other headphones).
    static func detect(name: String, productID: Int?) -> AirPodsModel? {
        if let productID {
            switch productID {
            case 0x200E: return .airPodsPro
            case 0x2014, 0x2024: return .airPodsPro2
            case 0x2027: return .airPodsPro3
            case 0x200A, 0x201F: return .airPodsMax
            case 0x201B: return .airPods4ANC
            case 0x2002, 0x200F, 0x2013, 0x2019: return nil   // AirPods 1, 2, 3, 4: no listening modes
            default: break
            }
        }
        let n = name.lowercased()
        if n.contains("airpods pro") || n.contains("airpods max") { return .unknownWithListeningModes }
        return nil
    }

    /// Modes the model can have (Off for AirPods Pro only when "Off" is turned on in the AirPods'
    /// settings; the Sound menu shows what is actually offered).
    var supportedModes: [AirPodsListeningMode] {
        switch self {
        case .airPodsPro, .airPodsMax: return [.off, .transparency, .noiseCancellation]
        case .airPodsPro2, .airPodsPro3, .airPods4ANC, .unknownWithListeningModes:
            return [.off, .transparency, .adaptive, .noiseCancellation]
        }
    }

    var systemImage: String {
        switch self {
        case .airPodsMax: return "airpodsmax"
        case .airPods4ANC: return "airpods.gen4"
        default: return "airpodspro"
        }
    }

    /// The Bluetooth address in a CoreAudio Bluetooth device UID ("18-3F-70-69-CE-57:output"),
    /// normalised to "18:3f:70:69:ce:57"; nil when the UID does not start with one.
    static func bluetoothAddress(fromUID uid: String) -> String? {
        let head = uid.prefix(17)
        guard head.count == 17 else { return nil }
        let parts = head.split(whereSeparator: { $0 == "-" || $0 == ":" })
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        return parts.joined(separator: ":").lowercased()
    }
}

// MARK: - Sound menu parsing (pure)

/// One element of the Sound menu's AX tree, in depth-first order.
struct ControlCenterAXNode: Equatable, Sendable {
    var role: String
    var identifier: String?
    var title: String?
    var axDescription: String?
    /// AXValue as an integer (checkbox / disclosure state), when it is a number.
    var value: Int?

    var label: String {
        if let title, !title.isEmpty { return title }
        return axDescription ?? ""
    }
}

struct ControlCenterSoundMenuLayout: Equatable, Sendable {
    struct DeviceRow: Equatable, Sendable {
        var index: Int
        /// The device name, from the row's identifier ("sound-device-<name>").
        var name: String
        var identifier: String
        var isSelected: Bool
    }

    struct ModeItem: Equatable, Sendable {
        var mode: AirPodsListeningMode
        var index: Int
        var isSelected: Bool
    }

    var devices: [DeviceRow] = []

    var target: DeviceRow?
    /// The listening-mode checkboxes of `target` (empty while its section is collapsed).
    var modes: [ModeItem] = []
    /// The disclosure triangle of `target`, when there is one.
    var disclosureIndex: Int?
    var disclosureExpanded: Bool = false

    var selectedMode: AirPodsListeningMode? { modes.first(where: \.isSelected)?.mode }
    var availableModes: [AirPodsListeningMode] { modes.map(\.mode) }
    func item(for mode: AirPodsListeningMode) -> ModeItem? { modes.first { $0.mode == mode } }
}

/// Finds the AirPods row and its listening-mode checkboxes in a snapshot of the Sound menu.
///
/// Structure (macOS 26, from open-source tools that drive this menu; docs/airpods.md): every
/// output device is an AXCheckBox whose AXIdentifier is "sound-device-<name>" and whose
/// AXDescription starts with the name ("AirPods Pro, 84%"); AXValue 1 = current output. Everything
/// that belongs to the device — a disclosure triangle and, while it is the output, one checkbox per
/// listening mode, then Conversation Awareness Off / On — carries the same identifier.
enum ControlCenterSoundMenuParser {
    static let devicePrefix = "sound-device-"
    private static let toggleRoles: Set<String> = ["AXCheckBox", "AXRadioButton"]

    static func parse(_ nodes: [ControlCenterAXNode], deviceName: String?) -> ControlCenterSoundMenuLayout {
        var layout = ControlCenterSoundMenuLayout()
        for (i, node) in nodes.enumerated() where toggleRoles.contains(node.role) {
            guard let id = node.identifier, id.hasPrefix(devicePrefix) else { continue }
            let name = String(id.dropFirst(devicePrefix.count))
            guard !name.isEmpty, (node.axDescription ?? node.title ?? "").hasPrefix(name) else { continue }
            layout.devices.append(.init(index: i, name: name, identifier: id, isSelected: node.value == 1))
        }

        let wanted = deviceName?.trimmingCharacters(in: .whitespaces)
        layout.target = layout.devices.first { row in
            wanted.map { row.name.compare($0, options: [.caseInsensitive]) == .orderedSame } ?? false
        } ?? layout.devices.first { $0.isSelected && $0.name.localizedCaseInsensitiveContains("airpods") }
        guard let target = layout.target else { return layout }

        if let d = nodes.indices.first(where: { nodes[$0].role == "AXDisclosureTriangle" && nodes[$0].identifier == target.identifier }) {
            layout.disclosureIndex = d
            layout.disclosureExpanded = nodes[d].value == 1
        }

        // The listening-mode run: consecutive mode checkboxes of this device. "Off" counts only as
        // the first item (AirPods Max, or AirPods Pro with "Off" enabled) — a later "Off" is
        // Conversation Awareness. The run ends at the first other label or a repeated mode.
        var seen: Set<AirPodsListeningMode> = []
        for i in nodes.indices where i != target.index {
            let node = nodes[i]
            guard toggleRoles.contains(node.role), node.identifier == target.identifier else { continue }
            guard let mode = AirPodsListeningMode(controlCenterLabel: node.label),
                  !seen.contains(mode), !(mode == .off && !layout.modes.isEmpty) else {
                if layout.modes.isEmpty { continue } else { break }
            }
            seen.insert(mode)
            layout.modes.append(.init(mode: mode, index: i, isSelected: node.value == 1))
        }
        return layout
    }
}

// MARK: - Driver interface

enum AirPodsNoiseControlError: Error, Equatable, Sendable {
    case accessibilityNotGranted
    case screenLocked
    /// No Sound item in the menu bar (Control Center ▸ Sound set to "Don't Show in Menu Bar").
    case soundMenuNotFound
    case menuDidNotOpen

    case deviceNotInMenu
    /// The AirPods are in the menu but are not the current output.
    case deviceNotOutput
    /// No listening-mode items under the AirPods.
    case modesNotFound
    /// The menu does not offer this mode (e.g. "Off" not enabled for AirPods Pro).
    case modeUnavailable(AirPodsListeningMode)
    case pressFailed

    var message: String {
        switch self {
        case .accessibilityNotGranted: return String(localized: "Allow Accessibility access to switch the listening mode here.")
        case .screenLocked: return String(localized: "The screen is locked.")
        case .soundMenuNotFound: return String(localized: "Show Sound in the menu bar (System Settings ▸ Control Center ▸ Sound) to switch the listening mode here.")
        case .menuDidNotOpen: return String(localized: "The Sound menu did not open.")
        case .deviceNotInMenu: return String(localized: "The AirPods are not in the Sound menu.")
        case .deviceNotOutput: return String(localized: "The AirPods are not the current output.")
        case .modesNotFound: return String(localized: "The Sound menu shows no listening modes for these AirPods.")
        case .modeUnavailable(let mode): return String(localized: "\(mode.title) is not available for these AirPods.")
        case .pressFailed: return String(localized: "Could not select the listening mode.")
        }
    }
}

struct AirPodsListeningModeReading: Equatable, Sendable {
    var deviceName: String
    var mode: AirPodsListeningMode?
    var available: [AirPodsListeningMode]
}

enum AirPodsListeningModeRequest: Equatable, Sendable {
    case read(deviceName: String)
    case set(AirPodsListeningMode, deviceName: String)
}

/// Outcome of a Bluetooth product id lookup (system_profiler).
enum AirPodsProductIDLookup: Equatable, Sendable {
    case found(Int)
    /// Listed, but not an Apple device or without a product id: final (the name rule decides).
    case notApple
    /// The JSON was read but does not list the address (yet): retried later.
    case notListed
    /// system_profiler failed, timed out or printed no readable JSON: retried later.
    case failed
}

/// Performs one request against Control Center. Blocking (it waits for the menu to open and close),
/// so the service calls it on a background queue, one request at a time.
protocol AirPodsListeningModeDriving: AnyObject, Sendable {
    func perform(_ request: AirPodsListeningModeRequest) -> Result<AirPodsListeningModeReading, AirPodsNoiseControlError>
}

/// The Accessibility permission as the service sees it (PermissionCenter in the app, a fake in tests).
@MainActor
protocol AirPodsAccessibilityPermission: AnyObject {
    /// Last known state (observable through PermissionCenter).
    var isGranted: Bool { get }
    /// Re-reads the state from the system.
    func refresh()
    /// First time the system prompt, later System Settings ▸ Privacy & Security ▸ Accessibility.
    func request()
}

@MainActor
final class PermissionCenterAccessibility: AirPodsAccessibilityPermission {
    var isGranted: Bool { PermissionCenter.shared.isGranted(.accessibility) }
    func refresh() { PermissionCenter.shared.refresh(.accessibility) }
    func request() { PermissionCenter.shared.requestAccess(.accessibility) }
}

// MARK: - Service

/// AirPods that are the current output and have listening modes.
struct AirPodsNoiseControlTarget: Equatable, Sendable {
    var uid: String
    var name: String
    var model: AirPodsModel
}

@MainActor
@Observable
final class AirPodsNoiseControlService {
    static let shared = AirPodsNoiseControlService(driver: AirPodsControlCenterDriver(),
                                                   permission: PermissionCenterAccessibility())

    var accessibilityGranted: Bool { permission.isGranted }
    /// Last mode read or set, per device UID (nil until the menu was read once).
    private(set) var knownModes: [String: AirPodsListeningMode] = [:]
    /// Modes the Sound menu offered, per device UID (the model's list until it was read).
    private(set) var offeredModes: [String: [AirPodsListeningMode]] = [:]
    /// The mode a click asked for and that is not applied yet (shown as selected meanwhile).
    private(set) var pendingMode: [String: AirPodsListeningMode] = [:]
    private(set) var busyUID: String?
    private(set) var lastError: [String: AirPodsNoiseControlError] = [:]

    /// Minimum time between two openings of the Sound menu (each one is visible for a moment).
    @ObservationIgnored var minimumInterval: TimeInterval = 1.0
    @ObservationIgnored private let driver: AirPodsListeningModeDriving
    @ObservationIgnored private let permission: AirPodsAccessibilityPermission
    @ObservationIgnored private let queue = DispatchQueue(label: "AirPodsNoiseControl.driver", qos: .userInitiated)
    /// Bluetooth product id per address (observed: views re-evaluate `target(for:)` when it arrives).
    /// -1: looked up properly, and not an Apple device or not listed after `maxLookupAttempts`.
    private var productIDs: [String: Int] = [:]
    @ObservationIgnored private var lookingUp: Set<String> = []
    /// Unsuccessful lookups per address (system_profiler failed / timed out, or the address was not
    /// listed yet): retried after `lookupRetryInterval`, at most `maxLookupAttempts` times.
    @ObservationIgnored private var lookupFailures: [String: (count: Int, at: Date)] = [:]
    @ObservationIgnored var lookupRetryInterval: TimeInterval = 30
    @ObservationIgnored var maxLookupAttempts = 5
    @ObservationIgnored private var lastOperationEnd: Date = .distantPast
    @ObservationIgnored private var queued: [String: (target: AirPodsNoiseControlTarget, request: AirPodsListeningModeRequest)] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// Looks up the Bluetooth product id of an address (system_profiler); replaceable in tests.
    @ObservationIgnored var productIDLookup: @Sendable (String) -> AirPodsProductIDLookup = { AirPodsNoiseControlService.systemProfilerProductID($0) }

    init(driver: AirPodsListeningModeDriving, permission: AirPodsAccessibilityPermission) {
        self.driver = driver
        self.permission = permission
    }

    // MARK: Detection

    /// The AirPods-with-listening-modes target for the current output, or nil.
    func target(for output: AudioDevice?) -> AirPodsNoiseControlTarget? {
        guard let output, output.transport == .bluetooth else { return nil }
        var productID: Int?
        if let address = AirPodsModel.bluetoothAddress(fromUID: output.uid) {
            productID = productIDs[address]
            if productID == nil { lookUpProductID(address) }
        }
        guard let model = AirPodsModel.detect(name: output.name, productID: productID) else { return nil }
        return AirPodsNoiseControlTarget(uid: output.uid, name: output.name, model: model)
    }

    private func lookUpProductID(_ address: String) {
        guard !lookingUp.contains(address) else { return }
        if let failure = lookupFailures[address], Date().timeIntervalSince(failure.at) < lookupRetryInterval { return }
        lookingUp.insert(address)
        let lookup = productIDLookup
        Task.detached(priority: .utility) {
            let result = lookup(address)
            await MainActor.run { self.recordLookup(result, for: address) }
        }
    }

    /// A failed or premature lookup is not cached as "not AirPods": a timed-out system_profiler,
    /// or one that ran before a just-connected device appeared in its JSON, would otherwise hide the
    /// control for AirPods 4 (ANC; detected by product id only) until relaunch.
    private func recordLookup(_ result: AirPodsProductIDLookup, for address: String) {
        lookingUp.remove(address)
        switch result {
        case .found(let id):
            productIDs[address] = id
            lookupFailures[address] = nil
        case .notApple:
            productIDs[address] = -1   // the name rule decides
            lookupFailures[address] = nil
        case .notListed, .failed:
            let count = (lookupFailures[address]?.count ?? 0) + 1
            if count >= maxLookupAttempts {
                productIDs[address] = -1
                lookupFailures[address] = nil
            } else {
                lookupFailures[address] = (count, Date())
            }
        }
    }

    // MARK: State for the views

    func displayedMode(for target: AirPodsNoiseControlTarget) -> AirPodsListeningMode? {
        pendingMode[target.uid] ?? knownModes[target.uid]
    }

    func modes(for target: AirPodsNoiseControlTarget) -> [AirPodsListeningMode] {
        offeredModes[target.uid] ?? target.model.supportedModes
    }

    func isBusy(_ target: AirPodsNoiseControlTarget) -> Bool { busyUID == target.uid || queued[target.uid] != nil }

    func error(for target: AirPodsNoiseControlTarget) -> AirPodsNoiseControlError? { lastError[target.uid] }

    // MARK: Actions

    /// Switches the AirPods to `mode` (coalesced: clicks while a switch runs keep only the latest).
    func select(_ mode: AirPodsListeningMode, for target: AirPodsNoiseControlTarget) {
        refreshPermission()
        guard accessibilityGranted else { lastError[target.uid] = .accessibilityNotGranted; return }
        guard displayedMode(for: target) != mode || knownModes[target.uid] == nil else { return }
        pendingMode[target.uid] = mode
        enqueue(target, .set(mode, deviceName: target.name))
    }

    /// Reads the current mode (opens the Sound menu for a moment).
    func refresh(_ target: AirPodsNoiseControlTarget) {
        refreshPermission()
        guard accessibilityGranted else { lastError[target.uid] = .accessibilityNotGranted; return }
        // not while this device has a request waiting or running (a read must never replace a set)
        guard queued[target.uid] == nil, busyUID != target.uid else { return }
        enqueue(target, .read(deviceName: target.name))
    }

    func refreshPermission() {
        permission.refresh()
        if accessibilityGranted {
            for (uid, error) in lastError where error == .accessibilityNotGranted { lastError[uid] = nil }
        }
    }

    /// PermissionCenter: the system prompt the first time (macOS shows it once per app), later the
    /// Privacy pane.
    func requestAccessibility() { permission.request() }

    /// The fallback: System Settings ▸ Sound (the AirPods' own pane is reachable from there).
    func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Queue

    private func enqueue(_ target: AirPodsNoiseControlTarget, _ request: AirPodsListeningModeRequest) {
        if case .read = request, let waiting = queued[target.uid], case .set = waiting.request { return }
        queued[target.uid] = (target, request)   // a newer request replaces a waiting one (a set any)
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while let next = queued.first {
            let uid = next.key, job = next.value
            queued[uid] = nil
            busyUID = uid
            let wait = minimumInterval - Date().timeIntervalSince(lastOperationEnd)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            // A click that arrived during the wait replaced the job: take the newest — but a read
            // that arrived then never replaces a set (the user's switch would be dropped).
            let replacement = queued.removeValue(forKey: uid)
            let (target, request) = Self.preferred(job, replacement)
            let result = await run(request)
            lastOperationEnd = Date()
            busyUID = nil
            apply(result, request: request, target: target)
        }
        worker = nil
    }

    /// The request to run when `newer` arrived while `job` waited: the newer one, unless it is a
    /// read and `job` a set.
    static func preferred(_ job: (target: AirPodsNoiseControlTarget, request: AirPodsListeningModeRequest),
                          _ newer: (target: AirPodsNoiseControlTarget, request: AirPodsListeningModeRequest)?)
        -> (target: AirPodsNoiseControlTarget, request: AirPodsListeningModeRequest) {
        guard let newer else { return job }
        if case .read = newer.request, case .set = job.request { return job }
        return newer
    }

    private func run(_ request: AirPodsListeningModeRequest) async -> Result<AirPodsListeningModeReading, AirPodsNoiseControlError> {
        let driver = driver
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: driver.perform(request)) }
        }
    }

    private func apply(_ result: Result<AirPodsListeningModeReading, AirPodsNoiseControlError>,
                       request: AirPodsListeningModeRequest, target: AirPodsNoiseControlTarget) {
        let uid = target.uid
        let stillPending = queued[uid] != nil
        switch result {
        case .success(let reading):
            if let mode = reading.mode { knownModes[uid] = mode }
            if !reading.available.isEmpty { offeredModes[uid] = reading.available }
            lastError[uid] = nil
        case .failure(let error):
            lastError[uid] = error
            if error == .accessibilityNotGranted { permission.refresh() }
        }
        if !stillPending { pendingMode[uid] = nil }
    }

    // MARK: Product id

    /// `system_profiler SPBluetoothDataType -json` (documented system tool, ~0.5 s): the product id
    /// of the paired device with this address.
    nonisolated static func systemProfilerProductID(_ address: String) -> AirPodsProductIDLookup {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failed }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        // killed by the timeout, or failed: try again later
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return .failed }
        return productIDLookup(inSystemProfilerJSON: data, address: address)
    }

    /// The product id, or nil (not listed, not Apple, or unreadable JSON).
    nonisolated static func productID(inSystemProfilerJSON data: Data, address: String) -> Int? {
        if case .found(let id) = productIDLookup(inSystemProfilerJSON: data, address: address) { return id }
        return nil
    }

    nonisolated static func productIDLookup(inSystemProfilerJSON data: Data, address: String) -> AirPodsProductIDLookup {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return .failed }
        let wanted = address.lowercased().replacingOccurrences(of: "-", with: ":")
        for controller in controllers {
            for group in ["device_connected", "device_not_connected"] {
                for wrapper in controller[group] as? [[String: Any]] ?? [] {
                    for (_, value) in wrapper {
                        guard let d = value as? [String: Any],
                              (d["device_address"] as? String)?.lowercased().replacingOccurrences(of: "-", with: ":") == wanted
                        else { continue }
                        if let vendor = hexInt(d["device_vendorID"]), vendor != AirPodsModel.appleVendorID { return .notApple }
                        return hexInt(d["device_productID"]).map { .found($0) } ?? .notApple
                    }
                }
            }
        }
        return .notListed
    }

    private nonisolated static func hexInt(_ value: Any?) -> Int? {
        guard let s = value as? String else { return value as? Int }
        let token = s.split(separator: " ").first.map(String.init) ?? s
        return token.lowercased().hasPrefix("0x") ? Int(token.dropFirst(2), radix: 16) : Int(token)
    }
}

// MARK: - Settings

extension StoredKeys {
    /// Show the listening-mode control in the Audio widget when AirPods are the output.
    static let airPodsListeningModeControl = Key<Bool>("airPodsListeningModeControl", default: true)
}
