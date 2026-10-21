// Network widget (2026-10-20): the shown interface (Wi‑Fi network / Ethernet / VPN tunnel),
// Wi‑Fi signal, channel and rate, IPv4 / IPv6 (and optionally the public address), a VPN badge,
// and download / upload throughput with a 1–2 minute sparkline (Swift Charts). 4 grid cells
// (200 pt) × the 202 pt Nook cell. Apple-style per Support/NookWidgetChrome.swift.
// Data: NetworkMonitor.
import SwiftUI
import Charts

/// Fixed data for DEBUG previews (nothing is sampled).
struct NetworkWidgetPreviewData {
    var snapshot: NetworkSnapshot
    var history: [NetworkSample]
    var settings = NetworkWidgetSettings()
}

struct NetworkWidgetView: View {
    @State private var monitor = NetworkMonitor.shared
    @StoredSetting(.networkWidgetSettings) private var storedSettings
    var preview: NetworkWidgetPreviewData? = nil

    private var settings: NetworkWidgetSettings { preview?.settings ?? storedSettings }
    private var snapshot: NetworkSnapshot { preview?.snapshot ?? monitor.snapshot }
    private var history: [NetworkSample] { preview?.history ?? monitor.history }

    var body: some View {
        let snapshot = snapshot
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            if snapshot.isConnected, let iface = snapshot.interface {
                header(snapshot, iface)
                details(snapshot, iface)
                addresses(snapshot, iface)
                throughput(snapshot)
                NetworkSparkline(history: history, seconds: settings.historySeconds)
                    .frame(maxHeight: .infinity)
            } else {
                NookWidgetHeader("Network", systemImage: "network")
                NookWidgetEmptyState(
                    systemImage: "wifi.slash",
                    title: String(localized: "Not Connected"),
                    message: snapshot.wifi.map { $0.isPoweredOn ? nil : String(localized: "Wi‑Fi is turned off.") } ?? nil
                )
            }
        }
        .nookWidgetFrame()
        .onAppear { if preview == nil { monitor.setVisible(true) } }
        .onDisappear { if preview == nil { monitor.setVisible(false) } }
        .networkWidgetDebugHook()
    }

    // MARK: Header

    private func header(_ snapshot: NetworkSnapshot, _ iface: NetworkInterfaceInfo) -> some View {
        HStack(spacing: 6) {
            icon(snapshot, iface)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 20)
            Text(verbatim: title(snapshot, iface))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            if snapshot.vpnActive {
                vpnBadge(snapshot)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func icon(_ snapshot: NetworkSnapshot, _ iface: NetworkInterfaceInfo) -> some View {
        switch iface.kind {
        case .wifi:
            Image(systemName: "wifi", variableValue: Double(snapshot.wifi?.bars ?? 3) / 3)
        case .ethernet:
            Image(systemName: "cable.connector")
        case .tunnel:
            Image(systemName: "lock.shield")
        case .other:
            Image(systemName: "network")
        }
    }

    private func title(_ snapshot: NetworkSnapshot, _ iface: NetworkInterfaceInfo) -> String {
        switch iface.kind {
        case .wifi:     return snapshot.wifi?.ssid ?? "Wi‑Fi"
        case .ethernet: return String(localized: "Ethernet")   // the adapter name is on the detail line
        case .tunnel:   return String(localized: "VPN")
        case .other:    return iface.displayName
        }
    }

    private func vpnBadge(_ snapshot: NetworkSnapshot) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "lock.shield.fill")
            Text("VPN")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.green)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.green.opacity(0.16)))
        .help(String(localized: "VPN connected (\(snapshot.vpnInterfaces.joined(separator: ", ")))"))
        .accessibilityLabel(Text("VPN connected"))
    }

    // MARK: Details

    private func details(_ snapshot: NetworkSnapshot, _ iface: NetworkInterfaceInfo) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: firstDetailLine(snapshot, iface))
            if let second = secondDetailLine(snapshot, iface) {
                Text(verbatim: second)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func firstDetailLine(_ snapshot: NetworkSnapshot, _ iface: NetworkInterfaceInfo) -> String {
        var parts: [String] = []
        if iface.kind == .wifi, let wifi = snapshot.wifi, wifi.isAssociated {
            if let standard = wifi.standard { parts.append(standard) } else { parts.append("Wi‑Fi") }
            if let band = wifi.band { parts.append(band) }
            if let channel = wifi.channel { parts.append(String(localized: "Ch \(channel)")) }
        } else {
            parts.append(kindName(iface))
            if iface.linkSpeed > 0, iface.kind == .ethernet { parts.append(NetworkFormatting.linkSpeed(iface.linkSpeed)) }
        }
        parts.append(iface.bsdName)
        return parts.joined(separator: " · ")
    }

    private func secondDetailLine(_ snapshot: NetworkSnapshot, _ iface: NetworkInterfaceInfo) -> String? {
        if iface.kind == .wifi, let wifi = snapshot.wifi, wifi.isAssociated {
            var parts = ["\(wifi.rssi) dBm"]
            if wifi.transmitRate > 0 { parts.append(NetworkFormatting.megabits(wifi.transmitRate)) }
            if let security = wifi.security { parts.append(security) }
            return parts.joined(separator: " · ")
        }
        if let router = snapshot.router { return String(localized: "Router \(router)") }
        return nil
    }

    private func kindName(_ iface: NetworkInterfaceInfo) -> String {
        switch iface.kind {
        case .wifi:     return "Wi‑Fi"
        case .ethernet: return iface.displayName.isEmpty ? String(localized: "Ethernet") : iface.displayName
        case .tunnel:   return String(localized: "Tunnel")
        case .other:    return iface.displayName
        }
    }

    // MARK: Addresses

    private func addresses(_ snapshot: NetworkSnapshot, _ iface: NetworkInterfaceInfo) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 1) {
            if let v4 = iface.ipv4.first(where: { !$0.hasPrefix("169.254.") }) ?? iface.ipv4.first {
                addressRow("IPv4", v4)
            }
            if let v6 = iface.ipv6.min(by: { $0.count < $1.count }) {
                addressRow("IPv6", v6)
            }
            if settings.showsPublicIP {
                if let ip = snapshot.publicIP {
                    addressRow(String(localized: "Public"), ip)
                } else {
                    addressRow(String(localized: "Public"), snapshot.publicIPFailed ? "—" : "…")
                }
            }
        }
        .font(.caption)
    }

    private func addressRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(verbatim: label)
                .foregroundStyle(.tertiary)
                .gridColumnAlignment(.leading)
            Text(verbatim: value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Throughput

    private func throughput(_ snapshot: NetworkSnapshot) -> some View {
        HStack(spacing: 8) {
            rate("arrow.down", snapshot.download, color: NetworkSparkline.downloadColor, label: "Download")
            Spacer(minLength: 0)
            rate("arrow.up", snapshot.upload, color: NetworkSparkline.uploadColor, label: "Upload")
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
    }

    private func rate(_ symbol: String, _ value: Double, color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(verbatim: NetworkFormatting.rate(value))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: NetworkFormatting.rate(value)))
    }
}

// MARK: - Sparkline

struct NetworkSparkline: View {
    var history: [NetworkSample]
    var seconds: Int

    static let downloadColor = Color.blue
    static let uploadColor = Color.orange

    var body: some View {
        let now = history.last?.date ?? Date()
        let peak = history.reduce(0) { max($0, $1.download, $1.upload) }
        Chart {
            ForEach(history, id: \.date) { sample in
                AreaMark(x: .value("Time", sample.date),
                         y: .value("Rate", sample.download),
                         series: .value("Direction", "down"))
                    .foregroundStyle(NookSparklineStyle.areaGradient(Self.downloadColor, top: 0.45, bottom: 0.05))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", sample.date),
                         y: .value("Rate", sample.download),
                         series: .value("Direction", "down"))
                    .foregroundStyle(Self.downloadColor)
                    .lineStyle(NookSparklineStyle.lineStroke)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", sample.date),
                         y: .value("Rate", sample.upload),
                         series: .value("Direction", "up"))
                    .foregroundStyle(Self.uploadColor)
                    .lineStyle(NookSparklineStyle.lineStroke)
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: now.addingTimeInterval(-Double(seconds))...now)
        .chartYScale(domain: 0...max(peak * 1.15, 2_048))
        // explicit plot colour: inside a chart, hierarchical styles resolve against the marks' tint
        .nookSparklineChrome(cornerRadius: 6, plotFill: Color.primary.opacity(0.06),
                             showsPlaceholder: history.count < 2, placeholder: Text("Measuring…"),
                             placeholderFont: .caption2)
        .overlay(alignment: .topLeading) {
            if peak > 0 {
                Text(verbatim: NetworkFormatting.rate(peak))
                    .font(.system(size: 8, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
        .frame(minHeight: 24)
        .accessibilityLabel(Text("Network throughput, last \(seconds) seconds"))
    }
}

// MARK: - Formatting

enum NetworkFormatting {
    /// Bytes per second, decimal units like Activity Monitor ("1.2 MB/s").
    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(bytesPerSecond, 0)
        var unit = 0
        while value >= 999.5, unit < units.count - 1 { value /= 1000; unit += 1 }
        if unit == 0 { return "\(Int(value.rounded())) \(units[0])" }
        return String(format: value < 9.95 ? "%.1f %@" : "%.0f %@", value, units[unit])
    }

    /// Mb/s value (Wi‑Fi transmit rate).
    static func megabits(_ mbps: Double) -> String {
        mbps >= 1000 ? String(format: "%.1f Gb/s", mbps / 1000) : "\(Int(mbps.rounded())) Mb/s"
    }

    /// Link speed in bits/s.
    static func linkSpeed(_ bitsPerSecond: UInt64) -> String {
        let value = Double(bitsPerSecond)
        if value >= 1e9 { return String(format: value.truncatingRemainder(dividingBy: 1e9) == 0 ? "%.0f Gb/s" : "%.1f Gb/s", value / 1e9) }
        return "\(Int((value / 1e6).rounded())) Mb/s"
    }
}
