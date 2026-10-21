// Sampler of the System widget (NookWidget.systemStats, 2026-10-20).
//
// Public, read-only sources only (no private frameworks, no helper, no SMC):
//   CPU      host_processor_info(PROCESSOR_CPU_LOAD_INFO) tick deltas, total and per cluster
//            (E/P from IODeviceTree `cpus/*` "cluster-type" by "logical-cpu-id", read once;
//            fallback: the first hw.perflevel1.logicalcpu CPUs are efficiency cores)
//   memory   host_statistics64(HOST_VM_INFO64): used = app (internal − purgeable) + wired +
//            compressed (Activity Monitor's "Memory Used"), hw.memsize, vm.swapusage,
//            kern.memorystatus_vm_pressure_level (1 normal / 2 warning / 4 critical)
//   disk     IORegistry IOBlockStorageDriver "Statistics" Bytes (Read)/(Write), summed, deltas/s
//   GPU      IORegistry IOAccelerator "PerformanceStatistics": "Device Utilization %", else
//            "GPU Activity(%)", else "Renderer Utilization %" (first that exists)
//   other    ProcessInfo.thermalState, getloadavg, kern.boottime
// Sampling runs every 2 s on a utility queue (timer leeway 250 ms) while the widget is in the
// Nook or a System view is visible (WidgetPresence; 30 s grace after removal); samples are
// published to the main actor. A sample costs a few syscalls and two small
// IORegistry lookups (measured in BUILD-LOG). History keeps the last 5 min (150 samples).
import Foundation
import IOKit
import Darwin
import Observation

struct SystemStatsSample: Sendable, Equatable {
    var date: Date
    /// 0…1, nil on the first sample (no delta yet).
    var cpu: Double?
    var cpuPerformance: Double?
    var cpuEfficiency: Double?
    /// 0…1, nil when no IOAccelerator reports a utilisation.
    var gpu: Double?
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryCompressed: UInt64
    var swapUsed: UInt64
    /// kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical (0 = unknown).
    var memoryPressure: Int
    /// Bytes per second, nil on the first sample.
    var diskRead: Double?
    var diskWrite: Double?
    var load: (Double, Double, Double)
    var thermal: ProcessInfo.ThermalState

    static func == (a: Self, b: Self) -> Bool { a.date == b.date }

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
}

@MainActor
@Observable
final class SystemStatsMonitor {
    static let shared = SystemStatsMonitor()

    static let interval: TimeInterval = 2
    static let maxHistory: TimeInterval = 5 * 60

    private(set) var samples: [SystemStatsSample] = []
    var latest: SystemStatsSample? { samples.last }
    /// The IOAccelerator key the GPU value is read from (nil until found / none on this Mac).
    private(set) var gpuKey: String?
    /// Boot time (kern.boottime), for the uptime.
    let bootDate: Date? = SystemStatsSampler.bootDate()
    private(set) var isRunning = false

    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private let queue = DispatchQueue(label: "SystemStatsMonitor", qos: .utility)
    @ObservationIgnored private let sampler = SystemStatsSampler()
    /// Samples while the widget is in the Nook or a view is visible; a removed widget keeps
    /// sampling for 30 s (a quick remove / re-add keeps the sparklines' history).
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(.systemStats, label: "SystemStats", idleGrace: Self.idleGrace,
                                      onNeeded: { [unowned self] in self.startSampling() },
                                      onIdle: { [unowned self] in self.stopSampling() })
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in self.timer != nil }
        #endif
        return presence
    }()

    static let idleGrace: TimeInterval = 30

    /// Starts sampling (idempotent). Called when the widget appears; sampling then continues while
    /// the widget stays in the Nook (also with the notch closed, so the sparklines have history).
    /// Without the widget in the Nook (and no `setVisible(true)`), it stops after `idleGrace`.
    func start() {
        presence.touch()
    }

    /// A System view appeared (true) or disappeared (false): sampling also runs while one is
    /// visible. Balanced calls.
    func setVisible(_ visible: Bool) {
        presence.setVisible(visible)
    }

    /// Stops sampling now (the next `start()` / `setVisible(true)` / Nook change applies the state again).
    func stop() {
        presence.forceIdle()
    }

    private func startSampling() {
        guard timer == nil else { return }
        isRunning = true
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(250))
        let sampler = self.sampler
        // forget the counters of an earlier run: the first sample after a restart would otherwise
        // average CPU / disk over the whole stopped period (the queue is serial and this is queued
        // before the timer resumes, so it runs before the first sample)
        queue.async { sampler.reset() }
        t.setEventHandler { [weak self] in
            let (sample, key) = sampler.sample()
            DispatchQueue.main.async { self?.append(sample, gpuKey: key) }
        }
        timer = t
        t.resume()
    }

    private func stopSampling() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    private func append(_ sample: SystemStatsSample, gpuKey key: String?) {
        // a sample queued just before the timer was cancelled
        guard timer != nil else { return }
        presence.debugCheckTick("sampling")
        if gpuKey != key { gpuKey = key }
        let cutoff = sample.date.addingTimeInterval(-Self.maxHistory - Self.interval)
        var s = samples
        s.removeAll { $0.date < cutoff }
        s.append(sample)
        samples = s
    }

    /// Samples within the last `window` seconds.
    func history(window: TimeInterval, now: Date = Date()) -> [SystemStatsSample] {
        let start = now.addingTimeInterval(-window)
        return samples.filter { $0.date >= start }
    }
}

/// Confined to the monitor's serial queue.
final class SystemStatsSampler: @unchecked Sendable {
    private var previousTicks: [[UInt32]] = []
    private var previousDisk: (read: UInt64, write: UInt64, date: Date)?
    private let clusterIsEfficiency: [Bool]
    private let pageSize: UInt64
    private let memoryTotal: UInt64
    private var gpuKey: String?
    private var gpuLookups = 0

    /// Drops the previous CPU ticks / disk counters, so the next sample has no delta (as on a cold start).
    func reset() {
        previousTicks = []
        previousDisk = nil
    }

    init() {
        pageSize = UInt64(Self.sysctlInt("hw.pagesize") ?? 16384)
        memoryTotal = UInt64(Self.sysctlInt("hw.memsize") ?? 0)
        clusterIsEfficiency = Self.clusterMap()
    }

    func sample() -> (SystemStatsSample, String?) {
        let now = Date()
        let cpu = cpuUsage()
        let mem = memory()
        let disk = diskThroughput(now: now)
        var loads = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loads, 3)
        let sample = SystemStatsSample(
            date: now, cpu: cpu.total, cpuPerformance: cpu.p, cpuEfficiency: cpu.e,
            gpu: gpuUtilization(),
            memoryUsed: mem.used, memoryTotal: memoryTotal, memoryCompressed: mem.compressed,
            swapUsed: Self.swapUsed(), memoryPressure: Self.sysctlInt("kern.memorystatus_vm_pressure_level") ?? 0,
            diskRead: disk?.read, diskWrite: disk?.write,
            load: (loads[0], loads[1], loads[2]),
            thermal: ProcessInfo.processInfo.thermalState)
        return (sample, gpuKey)
    }

    // MARK: CPU

    private func cpuUsage() -> (total: Double?, p: Double?, e: Double?) {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return (nil, nil, nil) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let n = Int(count)
        let states = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        ticks.reserveCapacity(n)
        for cpu in 0..<n {
            var row = [UInt32](repeating: 0, count: states)
            for s in 0..<states { row[s] = UInt32(bitPattern: info[cpu * states + s]) }
            ticks.append(row)
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == n else { return (nil, nil, nil) }
        var busy = [0.0, 0.0, 0.0], total = [0.0, 0.0, 0.0] // all, P, E
        for cpu in 0..<n {
            let cur = ticks[cpu], prev = previousTicks[cpu]
            let d = (0..<states).map { Double(cur[$0] &- prev[$0]) }
            let idle = d[Int(CPU_STATE_IDLE)]
            let all = d.reduce(0, +)
            let group = cpu < clusterIsEfficiency.count && clusterIsEfficiency[cpu] ? 2 : 1
            busy[0] += all - idle; total[0] += all
            busy[group] += all - idle; total[group] += all
        }
        func ratio(_ i: Int) -> Double? { total[i] > 0 ? min(max(busy[i] / total[i], 0), 1) : nil }
        let hasClusters = clusterIsEfficiency.contains(true) && clusterIsEfficiency.contains(false)
        return (ratio(0), hasClusters ? ratio(1) : nil, hasClusters ? ratio(2) : nil)
    }

    /// true = efficiency core, by logical CPU index.
    private static func clusterMap() -> [Bool] {
        var map: [Int: Bool] = [:]
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if cpus != 0 {
            var iterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS {
                var entry = IOIteratorNext(iterator)
                while entry != 0 {
                    if let id = property(entry, "logical-cpu-id") as? NSNumber,
                       let type = property(entry, "cluster-type") as? Data,
                       let first = type.first {
                        map[id.intValue] = first == UInt8(ascii: "E")
                    }
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iterator)
                }
                IOObjectRelease(iterator)
            }
            IOObjectRelease(cpus)
        }
        let n = sysctlInt("hw.ncpu") ?? 0
        if !map.isEmpty, map.count >= n {
            return (0..<n).map { map[$0] ?? false }
        }
        // fallback: Apple Silicon lists the efficiency cluster first
        let e = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        return (0..<n).map { $0 < e }
    }

    // MARK: Memory

    private func memory() -> (used: UInt64, compressed: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let app = UInt64(stats.internal_page_count) &- min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        return ((app + wired + compressed) * pageSize, compressed * pageSize)
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    // MARK: Disk

    private func diskThroughput(now: Date) -> (read: Double, write: Double)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return nil }
        var read: UInt64 = 0, write: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = Self.property(entry, "Statistics") as? [String: Any] {
                read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        defer { previousDisk = (read, write, now) }
        guard let prev = previousDisk else { return nil }
        let dt = now.timeIntervalSince(prev.date)
        guard dt > 0.1 else { return nil }
        // a disk that disappeared (ejected) lowers the sum: clamp at 0
        return (Double(read > prev.read ? read - prev.read : 0) / dt,
                Double(write > prev.write ? write - prev.write : 0) / dt)
    }

    // MARK: GPU

    private static let gpuKeys = ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"]

    private func gpuUtilization() -> Double? {
        // no accelerator with a known key: look again only every ~60 s
        if gpuKey == nil {
            gpuLookups += 1
            if gpuLookups > 1 && gpuLookups % 30 != 1 { return nil }
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        var best: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = Self.property(entry, "PerformanceStatistics") as? [String: Any] {
                for key in Self.gpuKeys {
                    if let value = (stats[key] as? NSNumber)?.doubleValue {
                        if gpuKey != key { gpuKey = key }
                        best = max(best ?? 0, value)
                        break
                    }
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return best.map { min(max($0 / 100, 0), 1) }
    }

    // MARK: Helpers

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4: return Int(Int32(truncatingIfNeeded: value))
        default: return Int(value)
        }
    }

    static func bootDate() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1e6)
    }
}
