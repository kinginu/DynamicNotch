// Review fixes (2026-10-21): failed capabilities reads are not repeated on every refresh, and the
// DDC channel map is rebuilt only when the external displays change (fake hardware only).
import Foundation
import CoreGraphics
import Testing
@testable import DynamicNotchApp

/// A DDC monitor whose capabilities string has no vcp() list, plus a display (Sidecar-like) that
/// never gets a DDC channel.
final class CountingDisplayHardware: DisplayHardware, @unchecked Sendable {
    let monitor = FakeDDCMonitor(capabilities: "(prot(monitor)type(lcd)model(NOVCP))")
    private let lock = NSLock()
    private var _channelBuilds = 0
    private var _list: [DisplayInfo]
    var channelBuilds: Int { lock.withLock { _channelBuilds } }

    static let monitorInfo = DisplayInfo(id: 3, name: "Monitor", isBuiltIn: false, isMain: true, vendor: 1, model: 2, serial: 3)
    static let sidecar = DisplayInfo(id: 9, name: "Sidecar", isBuiltIn: false, isMain: false, vendor: 4, model: 5, serial: 6)

    init() { _list = [Self.monitorInfo, Self.sidecar] }

    func setDisplays(_ list: [DisplayInfo]) { lock.withLock { _list = list } }

    @MainActor func displays() -> [DisplayInfo] { lock.withLock { _list } }
    func builtInBrightness(_ display: CGDirectDisplayID) -> Double? { nil }
    func canSetBuiltInBrightness(_ display: CGDirectDisplayID) -> Bool { false }
    func setBuiltInBrightness(_ value: Double, display: CGDirectDisplayID) -> Bool { false }
    func ddcChannels(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DDCChannel] {
        lock.withLock { _channelBuilds += 1 }
        return [Self.monitorInfo.id: DDCChannel(transport: monitor, timing: .immediate)]
    }
    var builtInBackendName: String { "Fake" }
    var builtInBrightnessIsApproximate: Bool { false }
    var supportsDDC: Bool { true }

    /// Capabilities requests the monitor received.
    var capabilityRequests: Int {
        monitor.messages.filter { $0.count >= 2 && $0[1] == DDCOpcode.capabilitiesRequest.rawValue }.count
    }
}

@MainActor
private func refresh(_ service: DisplayControlService) async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in service.refresh { c.resume() } }
}

@Suite("Displays refresh caching", .serialized)
@MainActor
struct DisplayControlRefreshCacheTests {
    @Test func failedCapabilitiesReadIsNotRepeated() async {
        let hw = CountingDisplayHardware()
        let service = DisplayControlService(hardware: hw, settings: { DisplaysWidgetSettings() })
        service.isManual = true
        await refresh(service)
        let first = hw.capabilityRequests
        #expect(first > 0)
        #expect(service.state(3).capabilities == nil)
        #expect(service.state(3).ddc == .available)        // brightness still answers
        await refresh(service)
        await refresh(service)
        #expect(hw.capabilityRequests == first)
    }

    @Test func channelsAreRebuiltOnlyWhenDisplaysChange() async {
        let hw = CountingDisplayHardware()
        let service = DisplayControlService(hardware: hw, settings: { DisplaysWidgetSettings() })
        service.isManual = true
        await refresh(service)
        #expect(hw.channelBuilds == 1)
        await refresh(service)                              // Sidecar still has no channel
        #expect(hw.channelBuilds == 1)
        hw.setDisplays([CountingDisplayHardware.monitorInfo])
        await refresh(service)
        #expect(hw.channelBuilds == 2)
        // a display set change also probes capabilities again
        let before = hw.capabilityRequests
        hw.setDisplays([CountingDisplayHardware.monitorInfo, CountingDisplayHardware.sidecar])
        await refresh(service)
        #expect(hw.capabilityRequests > before)
    }
}
