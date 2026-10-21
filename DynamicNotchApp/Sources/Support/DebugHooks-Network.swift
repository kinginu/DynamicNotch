// DEBUG-only checks of the Network widget (2026-10-20), registered with DebugCommandRegistry by
// DebugHooks.install (`networkWidgetDebugHook()` → `NetworkWidgetDebug.install()` still runs when
// the widget appears; it only re-registers).
//   netlog            log the monitor's interfaces, primary interface, Wi‑Fi, VPN and throughput
//   netpreview:<dir>  write <dir>/network-live-<dark|light>.png (live data), network-sample-<case>-dark.png
//                     for fixed sample data (wifi, wifi-nossid, ethernet-vpn, vpn-tunnel, offline)
//                     and network-settings-<dark|light>.png. Nothing is written except the PNGs.
import SwiftUI
import AppKit

extension View {
    /// DEBUG: (re-)registers the Network widget debug commands when the view first appears.
    func networkWidgetDebugHook() -> some View {
        #if DEBUG
        return onAppear { NetworkWidgetDebug.install() }
        #else
        return self
        #endif
    }
}

#if DEBUG
@MainActor
enum NetworkWidgetDebug {
    static func install() {
        DebugCommandRegistry.register("netlog", "log the interfaces, primary interface, Wi‑Fi, VPN and throughput") { _ in log() }
        DebugCommandRegistry.register("netpreview", usage: "netpreview:<dir>", "Network widget live + fixed samples (dark) + settings") { arg in
            WidgetSnapshotter.session(arg, tag: "[NetworkWidget]") { render(to: $0) }
        }
    }

    static func log() {
        let m = NetworkMonitor.shared
        NSLog("[NetworkWidget] primary=%@ router=%@ shown=%@ vpn=%@ down=%.0f up=%.0f history=%ld public=%@ failed=%d",
              m.primaryInterfaceName ?? "nil", m.router ?? "nil", m.shownInterfaceName ?? "nil",
              m.vpnInterfaces.joined(separator: ","), m.download, m.upload, m.history.count,
              m.publicIP ?? "nil", m.publicIPFailed ? 1 : 0)
        for i in m.interfaces {
            NSLog("[NetworkWidget]   %@ kind=%@ display=%@ v4=%@ v6=%@ link=%llu", i.bsdName, i.kind.rawValue,
                  i.displayName, i.ipv4.joined(separator: ","), i.ipv6.joined(separator: ","), i.linkSpeed)
        }
        if let w = m.wifi {
            NSLog("[NetworkWidget]   wifi ssid=%@ power=%d assoc=%d rssi=%ld noise=%ld ch=%@ band=%@ tx=%.0f std=%@ sec=%@",
                  w.ssid ?? "nil", w.isPoweredOn ? 1 : 0, w.isAssociated ? 1 : 0, w.rssi, w.noise, w.channel.map(String.init) ?? "nil",
                  w.band ?? "nil", w.transmitRate, w.standard ?? "nil", w.security ?? "nil")
        } else {
            NSLog("[NetworkWidget]   wifi nil")
        }
    }

    static func render(to dir: URL) {
        log()
        let width = NookWidgetLayout.width(of: .network)
        let height = NookWidgetLayout.cellHeight
        WidgetSnapshotter.widget("network-live", in: dir, width: width, height: height, alignment: .top, settle: 0.8) {
            NetworkWidgetView()
        }
        for (name, data) in samples() {
            WidgetSnapshotter.widget("network-sample-\(name)", in: dir, width: width, height: height, alignment: .top,
                                     appearances: [true], settle: 0.8) { NetworkWidgetView(preview: data) }
        }
        WidgetSnapshotter.settings("network-settings", in: dir, size: CGSize(width: 520, height: 520), settle: 0.8) {
            NetworkWidgetSettingsView()
        }
    }

    private static func samples() -> [(String, NetworkWidgetPreviewData)] {
        let now = Date()
        let history: [NetworkSample] = (0..<60).map { i in
            let t = Double(i)
            let burst = (20...34).contains(i) ? 4_200_000.0 * (1 - abs(t - 27) / 9) : 0
            return NetworkSample(date: now.addingTimeInterval(t - 59),
                                 download: 60_000 + burst + 25_000 * sin(t / 3),
                                 upload: 18_000 + (i % 9 == 0 ? 380_000 : 0) + 6_000 * cos(t / 2))
        }
        let wifiIface = NetworkInterfaceInfo(bsdName: "en0", displayName: "Wi‑Fi", kind: .wifi, isUp: true,
                                             ipv4: ["192.168.1.23"], ipv6: ["2001:db8:85a3::8a2e:370:7334"], linkSpeed: 0)
        let wifi = WiFiInfo(ssid: "Home Network", isPoweredOn: true, isAssociated: true, rssi: -54, noise: -94,
                            channel: 149, band: "5 GHz", transmitRate: 864, standard: "Wi‑Fi 6",
                            security: "WPA3 Personal", isSecure: true)
        var noSSID = wifi; noSSID.ssid = nil; noSSID.rssi = -71
        let ethernet = NetworkInterfaceInfo(bsdName: "en7", displayName: "USB 10/100/1G/2.5G LAN", kind: .ethernet, isUp: true,
                                            ipv4: ["10.0.4.18"], ipv6: [], linkSpeed: 1_000_000_000)
        let tunnel = NetworkInterfaceInfo(bsdName: "utun4", displayName: "VPN", kind: .tunnel, isUp: true,
                                          ipv4: ["100.64.0.7"], ipv6: ["fd7a:115c:a1e0::7"], linkSpeed: 0)
        var publicSettings = NetworkWidgetSettings(); publicSettings.showsPublicIP = true
        let last = history.last!
        return [
            ("wifi", .init(snapshot: NetworkSnapshot(interface: wifiIface, router: "192.168.1.1", wifi: wifi,
                                                     download: last.download, upload: last.upload), history: history)),
            ("wifi-nossid", .init(snapshot: NetworkSnapshot(interface: wifiIface, router: "192.168.1.1", wifi: noSSID,
                                                            download: 1_234_567, upload: 45_678), history: history)),
            ("ethernet-vpn", .init(snapshot: NetworkSnapshot(interface: ethernet, router: "10.0.4.1", vpnInterfaces: ["utun4"],
                                                             download: 512, upload: 128, publicIP: "203.0.113.42"),
                                   history: history, settings: publicSettings)),
            ("vpn-tunnel", .init(snapshot: NetworkSnapshot(interface: tunnel, vpnInterfaces: ["utun4"],
                                                           download: 88_000, upload: 9_000), history: Array(history.suffix(1)))),
            ("offline", .init(snapshot: NetworkSnapshot(interface: nil, wifi: WiFiInfo(ssid: nil, isPoweredOn: false, isAssociated: false,
                                                        rssi: 0, noise: 0, channel: nil, band: nil, transmitRate: 0,
                                                        standard: nil, security: nil, isSecure: false)), history: [])),
        ]
    }
}
#endif
