// DEBUG-only commands of the System widget (2026-10-20), registered with DebugCommandRegistry
// by DebugHooks.install (`SystemStatsDebug.install()`, also still called when the widget appears,
// only re-registers).
//   sysstats            log the latest sample, the GPU key found, the time one sample takes
//                       (50 runs) and this process's CPU use since the previous `sysstats`
//   syspreview:<dir>    write <dir>/system-<live|sample|compact>-<dark|light>.png (the widget
//                       offscreen at 250 × 202 pt; live = the monitor's samples, sample = a
//                       synthetic 2 min history, compact = CPU + Memory rows only) and
//                       settings-<dark|light>.png (Settings ▸ Widgets ▸ System at 520 pt)
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum SystemStatsDebug {
    private static var lastCPU: (Double, Date)?

    static func install() {
        DebugCommandRegistry.register("sysstats", "log the latest sample, GPU key, sampler cost, this process's CPU use") { _ in log() }
        DebugCommandRegistry.register("syspreview", usage: "syspreview:<dir>", "System widget live / sample / compact + settings") { arg in
            WidgetSnapshotter.session(arg, tag: "[SystemStats]") { preview(to: $0) }
        }
    }

    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    static func log() {
        let m = SystemStatsMonitor.shared
        let cpu = processCPUSeconds(), now = Date()
        if let (prev, at) = lastCPU {
            NSLog("[SystemStats] process CPU %.2f %% over %.0f s", (cpu - prev) / now.timeIntervalSince(at) * 100, now.timeIntervalSince(at))
        }
        lastCPU = (cpu, now)
        let probe = SystemStatsSampler()
        let t0 = Date()
        for _ in 0..<50 { _ = probe.sample() }
        NSLog("[SystemStats] sampler cost %.3f ms per sample (50 runs)", Date().timeIntervalSince(t0) * 1000 / 50)
        NSLog("[SystemStats] running=%d samples=%ld gpuKey=%@", m.isRunning, m.samples.count, m.gpuKey ?? "none")
        if let s = m.latest {
            NSLog("[SystemStats] cpu=%@ P=%@ E=%@ gpu=%@ mem=%.2f/%.2f GB comp=%.2f swap=%.2f pressure=%ld read=%@ write=%@ load=%.2f %.2f %.2f thermal=%ld",
                  "\(s.cpu ?? -1)", "\(s.cpuPerformance ?? -1)", "\(s.cpuEfficiency ?? -1)", "\(s.gpu ?? -1)",
                  Double(s.memoryUsed) / 1_073_741_824, Double(s.memoryTotal) / 1_073_741_824,
                  Double(s.memoryCompressed) / 1_073_741_824, Double(s.swapUsed) / 1_073_741_824, s.memoryPressure,
                  "\(s.diskRead ?? -1)", "\(s.diskWrite ?? -1)", s.load.0, s.load.1, s.load.2, s.thermal.rawValue)
        }
    }

    static func sampleHistory(now: Date = Date()) -> [SystemStatsSample] {
        (0..<60).map { i in
            let t = Double(i)
            let date = now.addingTimeInterval(-Double(59 - i) * 2)
            let cpu = 0.18 + 0.12 * sin(t / 6) + (i > 40 && i < 48 ? 0.45 : 0)
            return SystemStatsSample(
                date: date, cpu: cpu, cpuPerformance: min(cpu * 1.2, 1), cpuEfficiency: cpu * 0.7,
                gpu: 0.08 + 0.05 * sin(t / 4) + (i > 30 && i < 38 ? 0.5 : 0),
                memoryUsed: UInt64((11.2 + 0.4 * sin(t / 15)) * 1_073_741_824), memoryTotal: 17_179_869_184,
                memoryCompressed: 2_200_000_000, swapUsed: 1_400_000_000, memoryPressure: 1,
                diskRead: max(0, 2_000_000 * sin(t / 3)) + (i == 44 ? 48_000_000 : 0),
                diskWrite: max(0, 900_000 * cos(t / 5)),
                load: (2.31, 2.05, 1.88), thermal: .nominal)
        }
    }

    static func preview(to dir: URL) {
        let width = SystemStatsWidgetSettings.cells * NookWidgetLayout.cell
        let saved = SettingsStore[.systemStatsWidgetSettings]
        defer { SettingsStore[.systemStatsWidgetSettings] = saved }
        let cases: [(String, [SystemStatsSample]?, Set<SystemStatsWidgetSettings.Row>)] = [
            ("live", nil, saved.rows),
            ("sample", sampleHistory(), Set(SystemStatsWidgetSettings.Row.allCases)),
            ("compact", sampleHistory(), [.cpu, .memory]),
        ]
        for (name, samples, rows) in cases {
            var s = saved
            s.rows = rows
            SettingsStore[.systemStatsWidgetSettings] = s
            WidgetSnapshotter.widget("system-\(name)", in: dir, width: width) { SystemStatsWidgetView(previewSamples: samples) }
        }
        SettingsStore[.systemStatsWidgetSettings] = saved
        WidgetSnapshotter.settings("settings", in: dir, size: CGSize(width: 520, height: 520)) { SystemStatsWidgetSettingsView() }
    }
}
#endif
