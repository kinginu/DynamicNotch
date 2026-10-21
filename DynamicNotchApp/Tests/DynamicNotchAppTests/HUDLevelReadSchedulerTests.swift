// HUD: HUDLevelReadScheduler's failure handling (docs/hud.md) with a fake reader and clock —
// corebrightnessdiag is never run.
//   swift test --filter HUD
import Foundation
import Testing
@testable import DynamicNotchApp

/// Canned reads (the last one repeats) and a count; thread-safe (the scheduler reads off-main).
private final class FakeBrightnessReader: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [HUDCoreBrightness.Snapshot?]
    private(set) var calls = 0
    init(_ answers: [HUDCoreBrightness.Snapshot?]) { self.answers = answers }
    func read() -> HUDCoreBrightness.Snapshot? {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return answers.count > 1 ? answers.removeFirst() : answers[0]
    }
}

@MainActor
@Suite("HUD level reads")
struct HUDLevelReadSchedulerTests {
    private let level = HUDCoreBrightness.Snapshot(displayBrightness: 0.5, keyboardBrightness: nil)

    private func make(_ reader: FakeBrightnessReader, tool: Bool = true, clock: @escaping () -> Date)
        -> (HUDLevelReadScheduler, () -> [HUDCoreBrightness.Snapshot?]) {
        let scheduler = HUDLevelReadScheduler(reader: { reader.read() }, toolAvailable: { tool }, now: clock)
        scheduler.debounceInterval = 0
        var results: [HUDCoreBrightness.Snapshot?] = []
        scheduler.onResult = { results.append($0) }
        return (scheduler, { results })
    }

    private func settle(_ until: () -> Bool) async {
        for _ in 0..<200 where !until() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    @Test func aFailedReadBacksOffInsteadOfDisablingForGood() async {
        var now = Date(timeIntervalSince1970: 1_000)
        let reader = FakeBrightnessReader([nil, level])
        let (scheduler, results) = make(reader, clock: { now })

        scheduler.request()
        await settle { results().count == 1 }
        #expect(results() == [nil])
        #expect(scheduler.consecutiveFailures == 1)
        #expect(!scheduler.acceptsRequests)

        scheduler.request()                       // inside the 30 s cooldown: skipped
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(reader.calls == 1)

        now = now.addingTimeInterval(31)          // cooldown over: the next key reads again
        #expect(scheduler.acceptsRequests)
        scheduler.request()
        await settle { results().count == 2 }
        #expect(results() == [nil, level])
        #expect(scheduler.consecutiveFailures == 0)
        #expect(scheduler.cooldownUntil == nil)
    }

    @Test func onlyAMissingToolDisablesReads() async {
        let reader = FakeBrightnessReader([level])
        let (scheduler, results) = make(reader, tool: false, clock: Date.init)
        scheduler.request()
        scheduler.request()
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(reader.calls == 0)
        #expect(scheduler.toolMissing)
        #expect(results() == [nil])               // reported once: "level unknown"
    }
}
