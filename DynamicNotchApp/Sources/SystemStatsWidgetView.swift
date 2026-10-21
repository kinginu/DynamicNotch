// The System Nook widget (NookWidget.systemStats, 2026-10-20). 5 grid cells (250 pt) × the
// 202 pt row.
//
// Layout (Apple-style, NookWidgetChrome conventions; like the Temperature widget):
//   header   gauge + "System", the sparkline window ("2 min") on the right
//   rows     CPU (total; E/P cluster split), GPU (IOAccelerator utilisation), Memory (used of
//            total; swap + compressed; sparkline coloured by memory pressure green / yellow / red),
//            Disk (read / write per second, two lines). Each row: label + current value on the
//            left, a Swift Charts sparkline of the window on the right.
//   footer   thermal state (icon + word, orange/red when serious/critical), load averages, uptime
// Rows are chosen in the widget settings. Data: SystemStatsMonitor (2 s samples).
import SwiftUI
import Charts

struct SystemStatsWidgetView: View {
    @StoredSetting(.systemStatsWidgetSettings) private var settings

    /// Preview / debug rendering only: draw these samples instead of the monitor's.
    var previewSamples: [SystemStatsSample]? = nil

    private var monitor: SystemStatsMonitor { SystemStatsMonitor.shared }
    private var samples: [SystemStatsSample] { previewSamples ?? monitor.samples }

    var body: some View {
        content
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                if previewSamples == nil { monitor.start() }
                #if DEBUG
                SystemStatsDebug.install()
                #endif
            }
    }

    @ViewBuilder
    private var content: some View {
        let rows = settings.visibleRows
        let chartRows = rows.filter { $0 != .system }
        let all = samples
        let now = all.last?.date ?? Date()
        let window = settings.historySeconds
        let shown = all.filter { $0.date >= now.addingTimeInterval(-window) }
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            header(window: window)
            if rows.isEmpty {
                NookWidgetEmptyState(systemImage: "gauge.with.dots.needle.33percent",
                                     title: String(localized: "No rows selected"),
                                     message: String(localized: "Choose rows in Settings ▸ Nook ▸ Widgets ▸ System."))
            } else {
                ForEach(chartRows) { row in
                    rowView(row, samples: shown, latest: all.last, now: now, window: window)
                        .frame(maxHeight: chartRows.count <= 2 ? 52 : .infinity)
                }
                if rows.contains(.system) {
                    footer(all.last)
                }
                if chartRows.count <= 2 { Spacer(minLength: 0) }
            }
        }
    }

    // MARK: Header

    private func header(window: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .symbolRenderingMode(.hierarchical)
            Text("System")
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: "\(Int(window / 60)) \(String(localized: "min"))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: SystemStatsWidgetSettings.Row, samples: [SystemStatsSample],
                         latest: SystemStatsSample?, now: Date, window: TimeInterval) -> some View {
        switch row {
        case .cpu:
            metricRow(label: "CPU",
                      value: percent(latest?.cpu),
                      detail: settings.showsClusters ? clusterDetail(latest) : nil,
                      lines: [Line(id: "cpu", color: .blue, values: samples.map { ($0.date, $0.cpu) })],
                      domain: 0...1, now: now, window: window)
        case .gpu:
            metricRow(label: "GPU",
                      value: latest.map { percent($0.gpu) } ?? "--",
                      detail: latest != nil && latest?.gpu == nil ? String(localized: "Not available") : nil,
                      lines: [Line(id: "gpu", color: .cyan, values: samples.map { ($0.date, $0.gpu) })],
                      domain: 0...1, now: now, window: window)
        case .memory:
            let color = pressureColor(latest?.memoryPressure ?? 1)
            metricRow(label: "Memory",
                      value: latest.map { "\(gigabytes($0.memoryUsed)) / \(gigabytes($0.memoryTotal, decimals: 0)) GB" } ?? "--",
                      detail: latest.map { String(localized: "Swap \(gigabytes($0.swapUsed)) · Comp. \(gigabytes($0.memoryCompressed)) GB") },
                      pressure: latest.map { pressureName($0.memoryPressure) },
                      pressureColor: color,
                      lines: [Line(id: "mem", color: color, values: samples.map { ($0.date, $0.memoryFraction) })],
                      domain: 0...1, now: now, window: window)
        case .disk:
            let peak = samples.reduce(0.0) { max($0, $1.diskRead ?? 0, $1.diskWrite ?? 0) }
            metricRow(label: "Disk",
                      value: latest.map { "R \(throughput($0.diskRead))" } ?? "--",
                      secondValue: latest.map { "W \(throughput($0.diskWrite))" },
                      lines: [Line(id: "read", color: .blue, values: samples.map { ($0.date, $0.diskRead) }),
                              Line(id: "write", color: .purple, values: samples.map { ($0.date, $0.diskWrite) })],
                      domain: 0...max(peak * 1.1, 1_000_000), now: now, window: window)
        case .system:
            EmptyView()
        }
    }

    fileprivate struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    fileprivate struct ChartPoint: Identifiable {
        let date: Date
        let value: Double
        let series: String
        let color: Color
        var id: String { "\(series)@\(date.timeIntervalSinceReferenceDate)" }
    }

    fileprivate struct SparklineMark: ChartContent {
        let point: ChartPoint
        let base: Double
        let filled: Bool

        var body: some ChartContent {
            if filled {
                AreaMark(x: .value("Time", point.date),
                         yStart: .value("Base", base),
                         yEnd: .value("Value", point.value),
                         series: .value("Series", point.series))
                    .foregroundStyle(NookSparklineStyle.areaGradient(point.color, top: 0.35, bottom: 0.03))
                    .interpolationMethod(.monotone)
            }
            LineMark(x: .value("Time", point.date),
                     y: .value("Value", point.value),
                     series: .value("Series", point.series))
                .foregroundStyle(point.color)
                .lineStyle(NookSparklineStyle.lineStroke)
                .interpolationMethod(.monotone)
        }
    }

    fileprivate struct Line: Identifiable {
        let id: String
        let color: Color
        let values: [(Date, Double?)]
    }

    private func metricRow(label: LocalizedStringKey, value: String, secondValue: String? = nil,
                           detail: String? = nil, pressure: String? = nil, pressureColor: Color = .green,
                           lines: [Line], domain: ClosedRange<Double>, now: Date, window: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let pressure {
                        Circle().fill(pressureColor).frame(width: 5, height: 5)
                        Text(verbatim: pressure)
                            .font(.system(size: 9).weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                Text(verbatim: value)
                    .font(.system(size: secondValue == nil ? 13 : 11, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let secondValue {
                    Text(verbatim: secondValue)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let detail {
                    Text(verbatim: detail)
                        .font(.system(size: 9).weight(.medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: 104, alignment: .leading)
            .accessibilityElement(children: .combine)

            sparkline(lines, domain: domain, now: now, window: window)
                .accessibilityHidden(true)
        }
    }

    private func sparkline(_ lines: [Line], domain: ClosedRange<Double>, now: Date, window: TimeInterval) -> some View {
        let filled = lines.count == 1
        var points: [ChartPoint] = []
        for line in lines {
            for (index, segment) in segments(line.values).enumerated() {
                let series = "\(line.id)#\(index)"
                for p in segment {
                    points.append(ChartPoint(date: p.date, value: p.value, series: series, color: line.color))
                }
            }
        }
        let hasData = !points.isEmpty
        let base = domain.lowerBound
        return Chart(points) { point in
            SparklineMark(point: point, base: base, filled: filled)
        }
        .chartXScale(domain: now.addingTimeInterval(-window)...now)
        .chartYScale(domain: domain)
        .nookSparklineChrome(cornerRadius: 4, plotFill: .quinary,
                             showsPlaceholder: !hasData, placeholder: Text("Collecting…"),
                             placeholderFont: .system(size: 9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Runs of samples with a value, broken where a value is missing or the gap is > 5 s (sleep).
    private func segments(_ values: [(Date, Double?)]) -> [[Point]] {
        var result: [[Point]] = []
        var current: [Point] = []
        for (date, value) in values {
            guard let value else {
                if !current.isEmpty { result.append(current); current = [] }
                continue
            }
            if let last = current.last, date.timeIntervalSince(last.date) > SystemStatsMonitor.interval * 2.5 {
                result.append(current); current = []
            }
            current.append(Point(date: date, value: value))
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: Footer

    private func footer(_ latest: SystemStatsSample?) -> some View {
        let thermal = latest?.thermal ?? ProcessInfo.processInfo.thermalState
        return HStack(spacing: 8) {
            Label {
                Text(verbatim: thermalName(thermal))
            } icon: {
                Image(systemName: thermal == .critical || thermal == .serious ? "thermometer.high" : "thermometer.medium")
            }
            .foregroundStyle(thermalColor(thermal))
            .help(String(localized: "Thermal state"))
            Spacer(minLength: 0)
            if let load = latest?.load {
                Label {
                    Text(verbatim: String(format: "%.2f %.2f %.2f", load.0, load.1, load.2))
                } icon: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .help(String(localized: "Load average (1, 5, 15 min)"))
            }
            Spacer(minLength: 0)
            if let boot = monitor.bootDate {
                Label {
                    Text(verbatim: uptime(since: boot, now: latest?.date ?? Date()))
                } icon: {
                    Image(systemName: "clock")
                }
                .help(String(localized: "Uptime"))
            }
        }
        .labelStyle(CompactLabelStyle())
        .font(.system(size: 9).weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private struct CompactLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) {
                configuration.icon.imageScale(.small)
                configuration.title
            }
        }
    }

    // MARK: Formatting

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded())) %"
    }

    private func clusterDetail(_ s: SystemStatsSample?) -> String? {
        guard let s, let e = s.cpuEfficiency, let p = s.cpuPerformance else { return nil }
        return "E \(Int((e * 100).rounded())) % · P \(Int((p * 100).rounded())) %"
    }

    private func gigabytes(_ bytes: UInt64, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", Double(bytes) / 1_073_741_824)
    }

    private func throughput(_ bytesPerSecond: Double?) -> String {
        guard let b = bytesPerSecond else { return "--" }
        switch b {
        case ..<1_000: return "\(Int(b)) B/s"
        case ..<1_000_000: return String(format: "%.0f KB/s", b / 1_000)
        case ..<1_000_000_000: return String(format: b < 10_000_000 ? "%.1f MB/s" : "%.0f MB/s", b / 1_000_000)
        default: return String(format: "%.2f GB/s", b / 1_000_000_000)
        }
    }

    private func pressureName(_ level: Int) -> String {
        switch level {
        case 4: return String(localized: "Critical")
        case 2: return String(localized: "Warning")
        default: return String(localized: "Normal")
        }
    }

    private func pressureColor(_ level: Int) -> Color {
        switch level {
        case 4: return .red
        case 2: return .yellow
        default: return .green
        }
    }

    private func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return String(localized: "Nominal")
        case .fair: return String(localized: "Fair")
        case .serious: return String(localized: "Serious")
        case .critical: return String(localized: "Critical")
        @unknown default: return "--"
        }
    }

    private func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .serious: return .orange
        case .critical: return .red
        default: return .secondary
        }
    }

    private func uptime(since boot: Date, now: Date) -> String {
        let minutes = max(Int(now.timeIntervalSince(boot) / 60), 0)
        let d = minutes / 1440, h = (minutes % 1440) / 60, m = minutes % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
