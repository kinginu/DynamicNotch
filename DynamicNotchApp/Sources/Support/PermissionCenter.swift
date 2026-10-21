// PermissionCenter (2026-10-20): one model of every privacy permission the app uses.
//
//   permission        status                                   request (first time)                    callback
//   microphone        AVCaptureDevice.authorizationStatus      AVCaptureDevice.requestAccess(.audio)   – (polled)
//   camera            AVCaptureDevice.authorizationStatus      AVCaptureDevice.requestAccess(.video)   – (polled)
//   location          CLLocationManager.authorizationStatus    requestWhenInUseAuthorization           delegate
//   screenRecording   CGPreflightScreenCaptureAccess           CGRequestScreenCaptureAccess            – (polled)
//   accessibility     AXIsProcessTrusted                       AXIsProcessTrustedWithOptions(prompt)   "com.apple.accessibility.api"
//   bluetooth         CBManager.authorization                  creating a CBCentralManager             delegate
//   calendar          EKEventStore.authorizationStatus(.event) requestFullAccessToEvents               EKEventStoreChanged
//   reminders         EKEventStore.authorizationStatus(.rem.)  requestFullAccessToReminders            EKEventStoreChanged
//   inputMonitoring   IOHIDCheckAccess(ListenEvent) + prompted CGRequestListenEventAccess              – (polled)   F5: HUD media keys
//
// `request(_:)` is uniform: `.notDetermined` shows the system prompt; denied / restricted /
// limited open the right System Settings ▸ Privacy & Security pane (macOS prompts only once);
// granted / unavailable do nothing. Screen Recording and Accessibility have no "not determined"
// state in their APIs, so the first prompt is remembered in UserDefaults (`PromptKeys`, the keys
// CaptureManager / MenuBarItemsManager used before) and reported as `.notDetermined` until then:
// the first request only shows the system prompt (CGRequestScreenCaptureAccess returns false at
// once while it is up, so opening System Settings as well would cover the prompt); later requests
// open the pane.
//
// `.unavailable`: the app is not set up for the permission (no usage description in Info.plist —
// asking would crash the app — or, under the Hardened Runtime, no resource-access entitlement).
//
// Changes: `statuses` is @Observable (views just read `status(for:)`), and every change is posted
// as `PermissionCenter.didChangeNotification` (`observe(_:handler:)` wraps it) for managers that
// must react (start a meter, reload events). Sources: the callbacks above; a refresh of everything
// when the app becomes active; and a 2 s poll of the permissions without callbacks while someone
// called `beginMonitoring()` or for two minutes after a request / opening System Settings (the
// user is expected to flip the switch there).
import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreGraphics
import CoreLocation
import EventKit
import Observation
import Security

enum AppPermission: String, CaseIterable, Identifiable, Sendable {
    case microphone, camera, location, screenRecording, accessibility, bluetooth, calendar, reminders
    case inputMonitoring // F5: listen-only event tap of the HUD (HUDMonitor)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:      return String(localized: "Microphone")
        case .camera:          return String(localized: "Camera")
        case .location:        return String(localized: "Location Services")
        case .screenRecording: return String(localized: "Screen Recording")
        case .accessibility:   return String(localized: "Accessibility")
        case .bluetooth:       return String(localized: "Bluetooth")
        case .calendar:        return String(localized: "Calendars")
        case .reminders:       return String(localized: "Reminders")
        case .inputMonitoring: return String(localized: "Input Monitoring") // F5:
        }
    }

    /// Anchor of the System Settings ▸ Privacy & Security pane.
    var privacyAnchor: String {
        switch self {
        case .microphone:      return "Privacy_Microphone"
        case .camera:          return "Privacy_Camera"
        case .location:        return "Privacy_LocationServices"
        case .screenRecording: return "Privacy_ScreenCapture"
        case .accessibility:   return "Privacy_Accessibility"
        case .bluetooth:       return "Privacy_Bluetooth"
        case .calendar:        return "Privacy_Calendars"
        case .reminders:       return "Privacy_Reminders"
        case .inputMonitoring: return "Privacy_ListenEvent" // F5:
        }
    }

    /// `x-apple.systempreferences:` URL of the permission's Privacy pane.
    var systemSettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyAnchor)")!
    }

    /// Info.plist usage-description keys; one of them must be present (none needed: empty).
    fileprivate var usageDescriptionKeys: [String] {
        switch self {
        case .microphone:      return ["NSMicrophoneUsageDescription"]
        case .camera:          return ["NSCameraUsageDescription"]
        case .location:        return ["NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"]
        case .bluetooth:       return ["NSBluetoothAlwaysUsageDescription"]
        case .calendar:        return ["NSCalendarsFullAccessUsageDescription"]
        case .reminders:       return ["NSRemindersFullAccessUsageDescription"]
        case .screenRecording, .accessibility: return []
        case .inputMonitoring: return [] // F5:
        }
    }

    /// Hardened Runtime resource-access entitlement (nil: none exists for this permission).
    fileprivate var entitlement: String? {
        switch self {
        case .microphone:           return "com.apple.security.device.audio-input"
        case .camera:               return "com.apple.security.device.camera"
        case .location:             return "com.apple.security.personal-information.location"
        case .calendar, .reminders: return "com.apple.security.personal-information.calendars"
        case .screenRecording, .accessibility, .bluetooth: return nil
        case .inputMonitoring:      return nil // F5:
        }
    }

    /// Permissions whose status is only learned by asking again (no change callback).
    fileprivate var isPolled: Bool { self != .location }
}

enum PermissionStatus: String, Equatable, Sendable {
    /// Never asked: `request` shows the system prompt.
    case notDetermined
    case granted
    /// Partial access that does not cover what the app needs (calendar: write-only).
    case limited
    case denied
    /// Blocked by a profile / parental controls.
    case restricted
    /// The app is not set up for this permission (usage description / entitlement missing).
    case unavailable

    var isGranted: Bool { self == .granted }
    /// Only System Settings can change it now.
    var needsSystemSettings: Bool { self == .denied || self == .restricted || self == .limited }

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized:    self = .granted
        case .notDetermined: self = .notDetermined
        case .restricted:    self = .restricted
        case .denied:        self = .denied
        @unknown default:    self = .denied
        }
    }

    init(_ status: CBManagerAuthorization) {
        switch status {
        case .allowedAlways: self = .granted
        case .notDetermined: self = .notDetermined
        case .restricted:    self = .restricted
        case .denied:        self = .denied
        @unknown default:    self = .denied
        }
    }

    /// `.authorized` (the pre-macOS 14 name) has the raw value of `.fullAccess`.
    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .fullAccess:    self = .granted
        case .writeOnly:     self = .limited
        case .notDetermined: self = .notDetermined
        case .restricted:    self = .restricted
        case .denied:        self = .denied
        @unknown default:    self = .denied
        }
    }

    /// `servicesEnabled`: CLLocationManager.locationServicesEnabled() (only asked when authorized).
    init(_ status: CLAuthorizationStatus, servicesEnabled: @autoclosure () -> Bool) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted:    self = .restricted
        case .denied:        self = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            self = servicesEnabled() ? .granted : .denied
        @unknown default:    self = .denied
        }
    }
}

@MainActor
@Observable
final class PermissionCenter {
    static let shared = PermissionCenter()

    /// Posted (object: the center) when a status changes; userInfo `permission` (AppPermission) and
    /// `status` (PermissionStatus).
    nonisolated static let didChangeNotification = Notification.Name("DynamicNotch.PermissionCenter.didChange")

    /// Last known status of every permission (kept current, see the file header).
    private(set) var statuses: [AppPermission: PermissionStatus] = [:]

    /// UserDefaults flags: the system prompt was shown once (Screen Recording / Accessibility).
    private enum PromptKeys {
        static let screenCapture = "permissionPrompted.screenCapture"
        static let accessibility = "permissionPrompted.accessibility"

        static func key(for permission: AppPermission) -> String? {
            switch permission {
            case .screenRecording: return screenCapture
            case .accessibility:   return accessibility
            default:               return nil
            }
        }
    }

    @ObservationIgnored private let callbacks = PermissionCallbacks()
    @ObservationIgnored private var locationManager: CLLocationManager?
    /// Created by the first Bluetooth request (creating it is what shows the prompt).
    @ObservationIgnored private var bluetoothCentral: CBCentralManager?
    /// Used for calendar / reminder requests when the caller passes no store of its own.
    @ObservationIgnored private lazy var eventStore = EKEventStore()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var monitors = 0
    @ObservationIgnored private var pollUntil: Date = .distantPast

    /// How long permissions are polled after a request / opening System Settings.
    private static let settingsPollWindow: TimeInterval = 120
    private static let pollInterval: TimeInterval = 2

    private init() {
        callbacks.center = self
        for permission in AppPermission.allCases { statuses[permission] = query(permission) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PermissionCenter.shared.refreshAll() }
        })
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PermissionCenter.shared.refresh([.calendar, .reminders]) }
        })
        // posted when an app is added to / removed from the Accessibility list; AXIsProcessTrusted
        // reflects it a moment later
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { _ = PermissionCenter.shared.refresh(.accessibility) }
            }
        })
    }

    // MARK: - Status

    /// Last known status (observable). Call `refresh(_:)` to re-read it from the system.
    func status(for permission: AppPermission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    func isGranted(_ permission: AppPermission) -> Bool { status(for: permission).isGranted }

    /// Re-reads one permission from the system; publishes a change. Returns the new status.
    @discardableResult
    func refresh(_ permission: AppPermission) -> PermissionStatus {
        let new = query(permission)
        let old = statuses[permission]
        guard new != old else { return new }
        statuses[permission] = new
        NSLog("[Permissions] %@: %@ → %@", permission.rawValue, old?.rawValue ?? "-", new.rawValue)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self,
                                        userInfo: ["permission": permission, "status": new])
        return new
    }

    func refresh(_ permissions: [AppPermission]) {
        for permission in permissions { refresh(permission) }
    }

    func refreshAll() { refresh(AppPermission.allCases) }

    /// The app has what asking for `permission` requires (usage description, entitlement).
    nonisolated static func isConfigured(_ permission: AppPermission) -> Bool {
        configured[permission] ?? false
    }

    nonisolated private static let configured: [AppPermission: Bool] = {
        let task = SecTaskCreateFromSelf(nil)
        var result: [AppPermission: Bool] = [:]
        for permission in AppPermission.allCases {
            let keys = permission.usageDescriptionKeys
            let described = keys.isEmpty || keys.contains { Bundle.main.object(forInfoDictionaryKey: $0) != nil }
            var entitled = true
            if let entitlement = permission.entitlement {
                entitled = task.map { (SecTaskCopyValueForEntitlement($0, entitlement as CFString, nil) as? Bool) == true } ?? false
            }
            result[permission] = described && entitled
        }
        return result
    }()

    private func query(_ permission: AppPermission) -> PermissionStatus {
        guard Self.isConfigured(permission) else { return .unavailable }
        switch permission {
        case .microphone:
            return PermissionStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camera:
            return PermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .location:
            return PermissionStatus(location.authorizationStatus,
                                    servicesEnabled: CLLocationManager.locationServicesEnabled())
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : promptedStatus(permission)
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : promptedStatus(permission)
        case .bluetooth:
            return PermissionStatus(CBManager.authorization)
        case .calendar:
            return PermissionStatus(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return PermissionStatus(EKEventStore.authorizationStatus(for: .reminder))
        case .inputMonitoring: return HUDMonitor.listenEventStatus() // F5:
        }
    }

    /// Screen Recording / Accessibility while not granted: denied once the prompt was shown.
    private func promptedStatus(_ permission: AppPermission) -> PermissionStatus {
        guard let key = PromptKeys.key(for: permission) else { return .denied }
        return UserDefaults.standard.bool(forKey: key) ? .denied : .notDetermined
    }

    private var location: CLLocationManager {
        if let locationManager { return locationManager }
        let manager = CLLocationManager()
        manager.delegate = callbacks
        locationManager = manager
        return manager
    }

    // MARK: - Requests

    /// Asks for `permission`: the system prompt the first time, the Privacy pane afterwards.
    /// Returns the status once the prompt is answered (Screen Recording / Accessibility: at once —
    /// their prompts report nothing; changes arrive later through the poll). `eventStore`: the
    /// store a calendar / reminders manager reads from (so the grant applies to it).
    @discardableResult
    func request(_ permission: AppPermission, eventStore store: EKEventStore? = nil) async -> PermissionStatus {
        let current = refresh(permission)
        if current.needsSystemSettings { openSystemSettings(for: permission) }
        guard current == .notDetermined else { return current }
        extendPolling()
        switch permission {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .location:
            location.requestWhenInUseAuthorization()
            await waitUntilDetermined(permission)
        case .bluetooth:
            if bluetoothCentral == nil {
                bluetoothCentral = CBCentralManager(delegate: callbacks, queue: .main,
                                                    options: [CBCentralManagerOptionShowPowerAlertKey: false])
            }
            await waitUntilDetermined(permission)
        case .calendar:
            do { _ = try await (store ?? eventStore).requestFullAccessToEvents() }
            catch { NSLog("[Permissions] calendar request failed: %@", "\(error)") }
        case .reminders:
            do { _ = try await (store ?? eventStore).requestFullAccessToReminders() }
            catch { NSLog("[Permissions] reminders request failed: %@", "\(error)") }
        case .screenRecording:
            markPrompted(permission)
            _ = CGRequestScreenCaptureAccess()
        case .accessibility:
            markPrompted(permission)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring: HUDMonitor.requestListenEventAccess() // F5:
        }
        return refresh(permission)
    }

    /// `request` for button actions (fire and forget; `then` runs with the resulting status).
    func requestAccess(_ permission: AppPermission, eventStore: EKEventStore? = nil,
                       then: (@MainActor (PermissionStatus) -> Void)? = nil) {
        Task { @MainActor in
            let status = await request(permission, eventStore: eventStore)
            then?(status)
        }
    }

    /// Opens System Settings ▸ Privacy & Security at the permission's pane and watches for the
    /// change for a while.
    func openSystemSettings(for permission: AppPermission) {
        NSWorkspace.shared.open(permission.systemSettingsURL)
        extendPolling()
    }

    private func markPrompted(_ permission: AppPermission) {
        if let key = PromptKeys.key(for: permission) { UserDefaults.standard.set(true, forKey: key) }
    }

    /// Waits (≤ 60 s) until the user answered the prompt of a permission whose request API has no
    /// completion (location, Bluetooth).
    private func waitUntilDetermined(_ permission: AppPermission, timeout: TimeInterval = 60) async {
        let deadline = Date().addingTimeInterval(timeout)
        while refresh(permission) == .notDetermined, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: - Change notifications

    /// Calls `handler` on the main actor for each change of one of `permissions` (all when nil).
    /// Remove the returned token with NotificationCenter.default.removeObserver.
    @discardableResult
    func observe(_ permissions: Set<AppPermission>? = nil,
                 handler: @escaping @MainActor (AppPermission, PermissionStatus) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: Self.didChangeNotification, object: self, queue: .main) { note in
            guard let permission = note.userInfo?["permission"] as? AppPermission,
                  let status = note.userInfo?["status"] as? PermissionStatus,
                  permissions?.contains(permission) ?? true else { return }
            MainActor.assumeIsolated { handler(permission, status) }
        }
    }

    /// A view showing permission state appeared: polls the permissions without callbacks every
    /// 2 s until the matching `endMonitoring()`.
    func beginMonitoring() {
        monitors += 1
        refreshAll()
        updatePolling()
    }

    func endMonitoring() {
        monitors = max(monitors - 1, 0)
        updatePolling()
    }

    private func extendPolling() {
        pollUntil = Date().addingTimeInterval(Self.settingsPollWindow)
        updatePolling()
    }

    private var wantsPolling: Bool { monitors > 0 || Date() < pollUntil }

    private func updatePolling() {
        if wantsPolling, pollTimer == nil {
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
                MainActor.assumeIsolated { PermissionCenter.shared.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !wantsPolling {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func poll() {
        refresh(AppPermission.allCases.filter(\.isPolled))
        updatePolling()
    }

    // MARK: - Delegate callbacks

    fileprivate func systemReportedChange(_ permission: AppPermission) {
        _ = refresh(permission)
    }
}

/// CoreLocation / CoreBluetooth delegate of PermissionCenter (both deliver on the main queue).
/// Changes are applied on the next main-queue turn, never re-entrantly from inside a manager's
/// creation (CLLocationManager reports its status right after it gets a delegate).
private final class PermissionCallbacks: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate {
    weak var center: PermissionCenter?

    private func report(_ permission: AppPermission) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.center?.systemReportedChange(permission) }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        report(.location)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        report(.bluetooth)
    }
}
