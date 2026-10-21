// F7: AirPods listening mode — the pure parts (Sound-menu parser, model detection, UID / system_profiler
// parsing) and the service's queueing against a fake driver. Control Center is never touched.
//   swift test --filter AirPodsNoiseControl
import Foundation
import Testing
@testable import DynamicNotchApp

private func box(_ id: String?, _ title: String? = nil, desc: String? = nil, value: Int? = nil) -> ControlCenterAXNode {
    ControlCenterAXNode(role: "AXCheckBox", identifier: id, title: title, axDescription: desc, value: value)
}

private let airpods = "sound-device-Alex’s AirPods Pro"

/// The Sound menu as open-source tools describe it on macOS 26: header, slider, device rows, and
/// the selected AirPods' section (disclosure, listening modes, Conversation Awareness Off / On).
private func soundMenu(listening: [(String, Int)], expanded: Bool = true, airPodsSelected: Bool = true) -> [ControlCenterAXNode] {
    var nodes: [ControlCenterAXNode] = [
        ControlCenterAXNode(role: "AXWindow"),
        ControlCenterAXNode(role: "AXStaticText", title: "Sound"),
        ControlCenterAXNode(role: "AXSlider", identifier: "volume-slider", value: 40),
        ControlCenterAXNode(role: "AXScrollArea"),
        box("sound-device-MacBook Pro Speakers", desc: "MacBook Pro Speakers", value: airPodsSelected ? 0 : 1),
        box(airpods, desc: "Alex’s AirPods Pro, 84%", value: airPodsSelected ? 1 : 0),
        ControlCenterAXNode(role: "AXDisclosureTriangle", identifier: airpods, value: expanded ? 1 : 0),
    ]
    guard expanded else { return nodes }
    nodes.append(ControlCenterAXNode(role: "AXStaticText", title: "Listening Mode"))
    nodes += listening.map { box(airpods, $0.0, value: $0.1) }
    nodes.append(ControlCenterAXNode(role: "AXStaticText", title: "Conversation Awareness"))
    nodes += [box(airpods, "Off", value: 1), box(airpods, "On", value: 0)]
    nodes.append(box("sound-device-Living Room", desc: "Living Room", value: 0))
    return nodes
}

@Suite("AirPods Sound-menu parser")
struct SoundMenuParserTests {
    @Test func proWithoutOffStopsBeforeConversationAwareness() {
        let nodes = soundMenu(listening: [("Transparency", 0), ("Adaptive", 1), ("Noise Cancellation", 0)])
        let layout = ControlCenterSoundMenuParser.parse(nodes, deviceName: "Alex’s AirPods Pro")
        #expect(layout.devices.count == 3)
        #expect(layout.target?.name == "Alex’s AirPods Pro")
        #expect(layout.target?.isSelected == true)
        #expect(layout.availableModes == [.transparency, .adaptive, .noiseCancellation])
        #expect(layout.selectedMode == .adaptive)
        #expect(layout.disclosureExpanded)
    }

    @Test func offFirstIsAListeningMode() {
        let nodes = soundMenu(listening: [("Off", 1), ("Transparency", 0), ("Noise Cancellation", 0)])
        let layout = ControlCenterSoundMenuParser.parse(nodes, deviceName: "Alex’s AirPods Pro")
        #expect(layout.availableModes == [.off, .transparency, .noiseCancellation])
        #expect(layout.selectedMode == .off)
        // the press target is the first "Off", not Conversation Awareness's
        #expect(layout.item(for: .off)?.index == nodes.firstIndex { $0.title == "Off" })
    }

    @Test func collapsedSectionReportsDisclosure() {
        let nodes = soundMenu(listening: [], expanded: false)
        let layout = ControlCenterSoundMenuParser.parse(nodes, deviceName: "Alex’s AirPods Pro")
        #expect(layout.modes.isEmpty)
        #expect(layout.disclosureIndex == 6)
        #expect(layout.disclosureExpanded == false)
    }

    @Test func fallsBackToSelectedAirPodsWhenNameDiffers() {
        let nodes = soundMenu(listening: [("Transparency", 1), ("Adaptive", 0), ("Noise Cancellation", 0)])
        let layout = ControlCenterSoundMenuParser.parse(nodes, deviceName: "Renamed Headphones")
        #expect(layout.target?.identifier == airpods)
        #expect(layout.selectedMode == .transparency)
    }

    @Test func airPodsNotInMenu() {
        let nodes = [box("sound-device-MacBook Pro Speakers", desc: "MacBook Pro Speakers", value: 1)]
        let layout = ControlCenterSoundMenuParser.parse(nodes, deviceName: "Alex’s AirPods Pro")
        #expect(layout.target == nil)
    }

    @Test func deviceRowNeedsMatchingDescription() {
        // A mode checkbox shares the identifier but its description is not the device name.
        let nodes = [box(airpods, "Adaptive", desc: "Adaptive", value: 1)]
        #expect(ControlCenterSoundMenuParser.parse(nodes, deviceName: nil).devices.isEmpty)
    }

    @Test func labelsMatchCaseInsensitively() {
        #expect(AirPodsListeningMode(controlCenterLabel: "noise cancellation") == .noiseCancellation)
        #expect(AirPodsListeningMode(controlCenterLabel: " Transparency ") == .transparency)
        #expect(AirPodsListeningMode(controlCenterLabel: "On") == nil)
    }
}

@Suite("AirPods detection")
struct AirPodsDetectionTests {
    @Test func productIDs() {
        #expect(AirPodsModel.detect(name: "x", productID: 0x2024) == .airPodsPro2)   // verified on this Mac
        #expect(AirPodsModel.detect(name: "x", productID: 0x200A) == .airPodsMax)
        #expect(AirPodsModel.detect(name: "AirPods Pro", productID: 0x2019) == nil) // id wins over name
        #expect(AirPodsModel.airPodsMax.supportedModes == [.off, .transparency, .noiseCancellation])
    }

    @Test func nameFallback() {
        #expect(AirPodsModel.detect(name: "Alex’s AirPods Pro", productID: nil) == .unknownWithListeningModes)
        #expect(AirPodsModel.detect(name: "AirPods Max", productID: -1) == .unknownWithListeningModes)
        #expect(AirPodsModel.detect(name: "Alex’s AirPods", productID: nil) == nil)
        #expect(AirPodsModel.detect(name: "WH-1000XM4", productID: nil) == nil)
    }

    @Test func addressFromUID() {
        #expect(AirPodsModel.bluetoothAddress(fromUID: "18-3F-70-69-CE-57:output") == "18:3f:70:69:ce:57")
        #expect(AirPodsModel.bluetoothAddress(fromUID: "BuiltInSpeakerDevice") == nil)
        #expect(AirPodsModel.bluetoothAddress(fromUID: "18-3F-70-69-CE") == nil)
    }

    @Test func systemProfilerJSON() throws {
        // Shape of `system_profiler SPBluetoothDataType -json` on macOS 26 (values from this Mac).
        let json = """
        {"SPBluetoothDataType":[{"device_not_connected":[{"Alex’s AirPods Pro":{"device_address":"18:3F:70:69:CE:57",
        "device_minorType":"Headphones","device_productID":"0x2024","device_vendorID":"0x004C"}}],
        "device_connected":[{"Cornix":{"device_address":"D9:31:8A:05:EB:24","device_productID":"0x0001","device_vendorID":"0x1234"}}]}]}
        """
        let data = Data(json.utf8)
        #expect(AirPodsNoiseControlService.productID(inSystemProfilerJSON: data, address: "18:3f:70:69:ce:57") == 0x2024)
        #expect(AirPodsNoiseControlService.productID(inSystemProfilerJSON: data, address: "d9:31:8a:05:eb:24") == nil)
        #expect(AirPodsNoiseControlService.productID(inSystemProfilerJSON: data, address: "00:00:00:00:00:00") == nil)
        // the outcomes behind those nils: only "not Apple" is final
        #expect(AirPodsNoiseControlService.productIDLookup(inSystemProfilerJSON: data, address: "d9:31:8a:05:eb:24") == .notApple)
        #expect(AirPodsNoiseControlService.productIDLookup(inSystemProfilerJSON: data, address: "00:00:00:00:00:00") == .notListed)
        #expect(AirPodsNoiseControlService.productIDLookup(inSystemProfilerJSON: Data("garbage".utf8), address: "00:00:00:00:00:00") == .failed)
    }
}

/// Records requests; each takes `delay` and answers as if the press worked.
private final class FakeDriver: AirPodsListeningModeDriving, @unchecked Sendable {
    let lock = NSLock()
    var delay: TimeInterval = 0
    var current: AirPodsListeningMode = .noiseCancellation
    private(set) var requests: [AirPodsListeningModeRequest] = []
    /// When each request reached the driver (after `delay`).
    private(set) var requestTimes: [Date] = []

    func perform(_ request: AirPodsListeningModeRequest) -> Result<AirPodsListeningModeReading, AirPodsNoiseControlError> {
        Thread.sleep(forTimeInterval: delay)
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        requestTimes.append(Date())
        if case .set(let mode, _) = request { current = mode }
        return .success(AirPodsListeningModeReading(deviceName: "AirPods Pro", mode: current,
                                                    available: [.transparency, .adaptive, .noiseCancellation]))
    }
}

@MainActor
private final class FakePermission: AirPodsAccessibilityPermission {
    var isGranted = true
    private(set) var requests = 0
    func refresh() {}
    func request() { requests += 1 }
}

@MainActor
@Suite("AirPods service")
struct AirPodsServiceTests {
    let target = AirPodsNoiseControlTarget(uid: "18-3F-70-69-CE-57:output", name: "AirPods Pro", model: .airPodsPro2)

    private func waitIdle(_ service: AirPodsNoiseControlService) async {
        for _ in 0..<200 where service.isBusy(target) { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    @Test func notTrustedNeverCallsTheDriver() async {
        let fake = FakeDriver()
        let permission = FakePermission(); permission.isGranted = false
        let service = AirPodsNoiseControlService(driver: fake, permission: permission)
        service.select(.transparency, for: target)
        await waitIdle(service)
        #expect(fake.requests.isEmpty)
        #expect(service.error(for: target) == .accessibilityNotGranted)
    }

    @Test func selectUpdatesKnownModeAndOfferedModes() async {
        let fake = FakeDriver()
        let service = AirPodsNoiseControlService(driver: fake, permission: FakePermission())
        service.minimumInterval = 0
        #expect(service.modes(for: target) == [.off, .transparency, .adaptive, .noiseCancellation])
        service.select(.adaptive, for: target)
        #expect(service.displayedMode(for: target) == .adaptive)   // pending, shown at once
        await waitIdle(service)
        #expect(fake.requests == [.set(.adaptive, deviceName: "AirPods Pro")])
        #expect(service.displayedMode(for: target) == .adaptive)
        #expect(service.modes(for: target) == [.transparency, .adaptive, .noiseCancellation])
    }

    @Test func rapidClicksAreCoalesced() async {
        let fake = FakeDriver(); fake.delay = 0.15
        let service = AirPodsNoiseControlService(driver: fake, permission: FakePermission())
        service.minimumInterval = 0
        service.select(.transparency, for: target)
        try? await Task.sleep(nanoseconds: 30_000_000)   // the first one is running
        service.select(.adaptive, for: target)
        service.select(.noiseCancellation, for: target)
        service.select(.off, for: target)
        await waitIdle(service)
        #expect(fake.requests == [.set(.transparency, deviceName: "AirPods Pro"), .set(.off, deviceName: "AirPods Pro")])
        #expect(service.displayedMode(for: target) == .off)
    }

    @Test func readDuringTheRateLimitWaitDoesNotDropASet() async {
        let fake = FakeDriver()
        let service = AirPodsNoiseControlService(driver: fake, permission: FakePermission())
        service.minimumInterval = 0.3
        service.refresh(target)
        await waitIdle(service)
        service.select(.transparency, for: target)            // waits ~0.3 s before opening the menu
        try? await Task.sleep(nanoseconds: 50_000_000)
        service.refresh(target)                               // "Read Current Mode" meanwhile
        await waitIdle(service)
        #expect(fake.requests == [.read(deviceName: "AirPods Pro"), .set(.transparency, deviceName: "AirPods Pro")])
        #expect(service.displayedMode(for: target) == .transparency)
    }

    @Test func aWaitingReadNeverReplacesASet() {
        let set = (target: target, request: AirPodsListeningModeRequest.set(.adaptive, deviceName: "AirPods Pro"))
        let read = (target: target, request: AirPodsListeningModeRequest.read(deviceName: "AirPods Pro"))
        let newerSet = (target: target, request: AirPodsListeningModeRequest.set(.off, deviceName: "AirPods Pro"))
        #expect(AirPodsNoiseControlService.preferred(set, read).request == set.request)
        #expect(AirPodsNoiseControlService.preferred(set, newerSet).request == newerSet.request)
        #expect(AirPodsNoiseControlService.preferred(read, set).request == set.request)
        #expect(AirPodsNoiseControlService.preferred(set, nil).request == set.request)
    }

    @Test func failedProductIDLookupIsRetried() async {
        let service = AirPodsNoiseControlService(driver: FakeDriver(), permission: FakePermission())
        service.lookupRetryInterval = 0
        let answers = LookupAnswers([.failed, .notListed, .found(0x201B)])   // AirPods 4 (ANC): id only
        service.productIDLookup = { _ in answers.next() }
        let output = AudioDevice(id: 1, uid: "18-3F-70-69-CE-57:output", name: "AirPods 4", transport: .bluetooth,
                                 hasOutput: true, hasInput: true)
        var found: AirPodsNoiseControlTarget?
        for _ in 0..<200 {
            found = service.target(for: output)
            if found != nil { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(found?.model == .airPods4ANC)
        #expect(answers.calls == 3)
    }

    @Test func productIDLookupGivesUpAfterTheLimit() async {
        let service = AirPodsNoiseControlService(driver: FakeDriver(), permission: FakePermission())
        service.lookupRetryInterval = 0
        service.maxLookupAttempts = 2
        let answers = LookupAnswers([.failed, .failed, .found(0x201B)])
        service.productIDLookup = { _ in answers.next() }
        let output = AudioDevice(id: 1, uid: "18-3F-70-69-CE-57:output", name: "AirPods 4", transport: .bluetooth,
                                 hasOutput: true, hasInput: true)
        for _ in 0..<50 {
            _ = service.target(for: output)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(answers.calls == 2)   // cached as "not found" (-1) after two failures
        #expect(service.target(for: output) == nil)
    }

    @Test func minimumIntervalSpacesMenuOpenings() async {
        let fake = FakeDriver()
        let service = AirPodsNoiseControlService(driver: fake, permission: FakePermission())
        service.minimumInterval = 0.3
        service.refresh(target)
        await waitIdle(service)
        service.select(.transparency, for: target)
        await waitIdle(service)
        #expect(fake.requests.count == 2)
        // The spacing between the two driver calls, not the time since select(): on a slow
        // machine waitIdle() may return well after the first call ended, which shortens the
        // remaining wait without breaking the rule.
        if fake.requestTimes.count == 2 {
            #expect(fake.requestTimes[1].timeIntervalSince(fake.requestTimes[0]) >= 0.25)
        }
    }
}

/// Hands out canned lookup results in order (the last one repeats); thread-safe.
private final class LookupAnswers: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [AirPodsProductIDLookup]
    private(set) var calls = 0
    init(_ answers: [AirPodsProductIDLookup]) { self.answers = answers }
    func next() -> AirPodsProductIDLookup {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return answers.count > 1 ? answers.removeFirst() : answers[0]
    }
}
