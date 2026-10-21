// DisplayControlService and its helpers on fake hardware (no display is changed: the only
// "write" path exercised is FakeDDCMonitor / FakeDisplayHardware).
import Foundation
import CoreGraphics
import Testing
@testable import DynamicNotchApp

final class FakeDisplayHardware: DisplayHardware, @unchecked Sendable {
    let monitor = FakeDDCMonitor(capabilities: DDCCapabilitiesTests.dell)
    private let lock = NSLock()
    private var _builtIn: Double = 0.42
    private var _builtInWrites: [Double] = []
    var builtInWrites: [Double] { lock.withLock { _builtInWrites } }

    static let builtIn = DisplayInfo(id: 1, name: "Built-in Display", isBuiltIn: true, isMain: false,
                                     vendor: 1552, model: 41038, serial: 1)
    static let dell = DisplayInfo(id: 3, name: "DELL P3225QE", isBuiltIn: false, isMain: true,
                                  vendor: 4268, model: 17277, serial: 1093753164)

    @MainActor func displays() -> [DisplayInfo] { [Self.dell, Self.builtIn] }
    func builtInBrightness(_ display: CGDirectDisplayID) -> Double? { lock.withLock { _builtIn } }
    func canSetBuiltInBrightness(_ display: CGDirectDisplayID) -> Bool { true }
    func setBuiltInBrightness(_ value: Double, display: CGDirectDisplayID) -> Bool {
        lock.withLock { _builtIn = value; _builtInWrites.append(value) }
        return true
    }
    func ddcChannels(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DDCChannel] {
        [Self.dell.id: DDCChannel(transport: monitor, timing: .immediate)]
    }
    var builtInBackendName: String { "Fake" }
    var builtInBrightnessIsApproximate: Bool { false }
    var supportsDDC: Bool { true }
}

@MainActor
private func makeService(_ hw: FakeDisplayHardware, settings: DisplaysWidgetSettings = {
    var s = DisplaysWidgetSettings()
    s.showContrast = true
    return s
}()) async -> DisplayControlService {
    let service = DisplayControlService(hardware: hw, settings: { settings })
    service.isManual = true
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        service.refresh { c.resume() }
    }
    return service
}

/// Waits (up to 2 s) until the service has written everything.
@MainActor
private func settle(_ service: DisplayControlService) async throws {
    for _ in 0..<200 {
        if service.isIdle { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("service did not settle")
}

@Suite("Displays service", .serialized)
@MainActor
struct DisplayControlServiceTests {
    @Test func refreshReadsBuiltInAndDDCMonitor() async {
        let hw = FakeDisplayHardware()
        let service = await makeService(hw)
        #expect(service.displays.map(\.id) == [3, 1])
        let builtIn = service.state(1)
        #expect(builtIn.brightness == 0.42)
        #expect(builtIn.ddc == .notApplicable)
        #expect(builtIn.isSettable(.brightness))
        let dell = service.state(3)
        #expect(dell.ddc == .available)
        #expect(dell.brightness == 0.5)
        #expect(dell.contrast == 0.75)
        #expect(dell.inputSource == 0x0F)
        #expect(dell.capabilities?.model == "P3225QE")
        #expect(!dell.isAvailable(.volume))       // not advertised
        #expect(!dell.isSettable(.input))
    }

    @Test func setClampsAndWritesThroughDDC() async throws {
        let hw = FakeDisplayHardware()
        let service = await makeService(hw)
        #expect(service.set(.brightness, to: 1.7, on: 3))
        #expect(service.state(3).brightness == 1.0)
        try await settle(service)
        #expect(hw.monitor.values[0x10]?.current == 100)
        #expect(!service.set(.brightness, to: .nan, on: 3))
        #expect(!service.set(.input, to: 0.5, on: 3))
        #expect(!service.set(.volume, to: 0.5, on: 3))   // monitor has no speakers
        #expect(!service.set(.contrast, to: 0.5, on: 1)) // built-in: brightness only
    }

    @Test func rapidSlidesAreCoalescedLatestWins() async throws {
        let hw = FakeDisplayHardware()
        let service = await makeService(hw)
        for i in 0...20 { service.set(.contrast, to: Double(i) / 20, on: 3) }
        try await settle(service)
        let writes = hw.monitor.setRequests.filter { $0.code == 0x12 }
        #expect(writes.count <= 2)                 // first one immediately, then the latest
        #expect(writes.last?.value == 100)
        #expect(hw.monitor.values[0x12]?.current == 100)
    }

    @Test func builtInWritesGoToBacklight() async throws {
        let hw = FakeDisplayHardware()
        let service = await makeService(hw)
        service.set(.brightness, to: -0.2, on: 1)
        try await settle(service)
        #expect(hw.builtInWrites == [0])
    }

    @Test func disabledDisplayIsNotReadOrWritten() async {
        let hw = FakeDisplayHardware()
        var settings = DisplaysWidgetSettings()
        settings.setEnabled(false, FakeDisplayHardware.dell)
        let service = await makeService(hw, settings: settings)
        #expect(service.state(3).ddc == .disabled)
        #expect(hw.monitor.messages.isEmpty)
        #expect(!service.set(.brightness, to: 0.3, on: 3))
        #expect(settings.visible(service.displays).map(\.id) == [1])
    }

    @Test func performRunsCommandsOnMatchingDisplays() async throws {
        let hw = FakeDisplayHardware()
        let service = await makeService(hw)
        let changed = service.perform(DisplayControlCommand(parsing: "brightness +10% external")!)
        #expect(changed == [3])
        #expect(abs((service.state(3).brightness ?? 0) - 0.6) < 1e-9)
        #expect(service.perform(DisplayControlCommand(parsing: "brightness 30% all")!).sorted() == [1, 3])
        try await settle(service)
        #expect(hw.builtInWrites.last == 0.3)
    }
}

@Suite("Displays helpers")
struct DisplayHelperTests {
    @Test func rateLimiterCoalescesPerKey() {
        var l = CoalescingRateLimiter<String, Int>(minimumInterval: 0.1)
        let t0 = Date(timeIntervalSince1970: 1000)
        #expect(l.submit(1, for: "a", now: t0) == 0)
        #expect(l.submit(2, for: "a", now: t0) == nil)          // already scheduled: replaces
        #expect(l.submit(9, for: "b", now: t0) == 0)            // other key is independent
        #expect(l.flush(key: "a", now: t0) == 2)
        #expect(l.flush(key: "a", now: t0) == nil)
        let d = l.submit(3, for: "a", now: t0.addingTimeInterval(0.04))
        #expect(d != nil && abs(d! - 0.06) < 1e-6)
        #expect(l.submit(4, for: "a", now: t0.addingTimeInterval(0.2), interval: 1) == nil)
        #expect(l.flush(key: "a", now: t0.addingTimeInterval(0.1)) == 4)
        let d2 = l.submit(5, for: "a", now: t0.addingTimeInterval(0.15), interval: 1)
        #expect(d2 != nil && abs(d2! - 0.95) < 1e-6)
    }

    @Test func commandParsing() {
        #expect(DisplayControlCommand(parsing: "brightness 60%") == .init(control: .brightness, action: .set(0.6)))
        #expect(DisplayControlCommand(parsing: "Brightness +10% builtin") == .init(control: .brightness, action: .adjust(0.1), target: .builtIn))
        #expect(DisplayControlCommand(parsing: "contrast 0.5 main") == .init(control: .contrast, action: .set(0.5), target: .main))
        #expect(DisplayControlCommand(parsing: "volume -5 external") == .init(control: .volume, action: .adjust(-0.05), target: .external))
        #expect(DisplayControlCommand(parsing: "brightness 40 id:3")?.target == .id(3))
        #expect(DisplayControlCommand(parsing: "brightness 70 name:DELL")?.target == .name("DELL"))
        #expect(DisplayControlCommand(parsing: "brightness 250")?.action == .set(1))
        #expect(DisplayControlCommand(parsing: "input 15") == nil)          // read-only
        #expect(DisplayControlCommand(parsing: "brightness bright") == nil)
        #expect(DisplayControlCommand(parsing: "brightness 50 somewhere") == nil)
        #expect(DisplayControlCommand(parsing: "brightness") == nil)
        let c = DisplayControlCommand(control: .brightness, action: .adjust(-0.3))
        #expect(c.resolvedValue(current: 0.2) == 0)
        #expect(c.resolvedValue(current: nil) == nil)
        #expect(c.description == "brightness -30% all")
    }

    @Test func commandIsCodable() throws {
        let c = DisplayControlCommand(control: .volume, action: .set(0.25), target: .name("LG"))
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(DisplayControlCommand.self, from: data) == c)
    }

    @Test func matcherPairsBySerialThenByModel() {
        let displays = [DisplayIdentity(displayID: 3, vendor: 4268, model: 17277, serial: 1093753164),
                        DisplayIdentity(displayID: 2, vendor: 4268, model: 17277, serial: 1093817932),
                        DisplayIdentity(displayID: 7, vendor: 1, model: 2, serial: 0)]
        let endpoints = [DisplayIdentity(vendor: 4268, model: 17277, serial: 1093817932),   // dispext0
                         DisplayIdentity(vendor: 4268, model: 17277, serial: 1093753164),   // dispext1
                         DisplayIdentity(vendor: 1, model: 2, serial: 0)]
        #expect(DisplayMatcher.match(displays: displays, endpoints: endpoints) == [3: 1, 2: 0, 7: 2])
        // more displays than endpoints: each endpoint is used once
        let twins = [DisplayIdentity(displayID: 5, vendor: 1, model: 2, serial: 0),
                     DisplayIdentity(displayID: 6, vendor: 1, model: 2, serial: 0)]
        #expect(DisplayMatcher.match(displays: twins, endpoints: [endpoints[2]]) == [5: 0])
    }

    @Test func registryNodeNamesAndBacklightFraction() {
        #expect(DDCServiceLocator.nodeName(ofFramebufferParent: "dispext0@88000000") == "dispext0")
        #expect(DDCServiceLocator.nodeName(ofProxyParent: "dispext1:dcpav-service-epic:0") == "dispext1")
        #expect(RegistryBacklight.fraction(["min": 0, "max": 65536, "value": 32768]) == 0.5)
        #expect(RegistryBacklight.fraction(["min": 10, "max": 10, "value": 10]) == nil)
        #expect(RegistryBacklight.fraction(nil) == nil)
    }

    @Test func settingsToleratesMissingKeys() throws {
        let s = try JSONDecoder().decode(DisplaysWidgetSettings.self, from: Data(#"{"ddcEnabled":false}"#.utf8))
        #expect(!s.ddcEnabled && s.showVolume && s.refreshInterval == 30 && s.disabledDisplays.isEmpty)
        var t = DisplaysWidgetSettings()
        t.setEnabled(false, FakeDisplayHardware.dell)
        t.setEnabled(false, FakeDisplayHardware.dell)
        #expect(t.disabledDisplays == ["4268-17277-1093753164"])
        t.setEnabled(true, FakeDisplayHardware.dell)
        #expect(t.disabledDisplays.isEmpty)
    }
}
