// Data source of the Network widget (2026-10-20).
//
//   throughput  64-bit byte counters of every interface (sysctl NET_RT_IFLIST2 / if_data64, the
//               same counters `netstat -ib` prints; getifaddrs' if_data is 32-bit and wraps at
//               4 GB) sampled every `samplingInterval` seconds while the widget is in the Nook
//               or a Network view is visible (WidgetPresence), so the sparkline already has
//               history when the Nook opens. Cheap: one sysctl.
//   details     interfaces + IPv4/IPv6 addresses (getifaddrs), display names and types
//               (SCNetworkInterface), the primary interface and router (SCDynamicStore
//               State:/Network/Global/IPv4), Wi‑Fi (CoreWLAN) and VPN presence. Refreshed only
//               while a Network widget is visible (`setVisible`), off the main thread.
//   Wi‑Fi       CWInterface: rssi / noise / channel / band / tx rate / PHY mode / security. The
//               network name (ssid) needs Location Services authorization on macOS 14+ and is nil
//               without it; the widget then says "Wi‑Fi".
//   VPN         a tunnel interface (utun / ipsec / ppp / tun / tap / wg) that is the primary
//               interface, carries a scoped proxy configuration (CFNetworkCopySystemProxySettings
//               "__SCOPED__", how NetworkExtension VPNs show up) or has a routable IPv4 address.
//               The utun interfaces macOS keeps for its own services carry only IPv6 link-local
//               addresses and do not count.
//   public IP   https://api.ipify.org, only when `showsPublicIP` is on; refreshed when the primary
//               interface or VPN state changes and every 10 minutes while visible.
import Foundation
import CoreWLAN
import SystemConfiguration
import CFNetwork
import Darwin
import Observation

struct NetworkInterfaceInfo: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable { case wifi, ethernet, tunnel, other }

    var bsdName: String
    var displayName: String
    var kind: Kind
    var isUp: Bool
    var ipv4: [String]
    /// Global (routable) IPv6 addresses, without scope.
    var ipv6: [String]
    /// Link speed reported by the driver (bits/s; 0 = unknown).
    var linkSpeed: UInt64

    var id: String { bsdName }
    var hasRoutableAddress: Bool {
        ipv6.isEmpty == false || ipv4.contains { !$0.hasPrefix("169.254.") }
    }
}

struct WiFiInfo: Hashable, Sendable {
    /// Network name; nil without Location Services authorization (macOS 14+).
    var ssid: String?
    var isPoweredOn: Bool
    var isAssociated: Bool
    var rssi: Int
    var noise: Int
    var channel: Int?
    /// "2.4 GHz" / "5 GHz" / "6 GHz".
    var band: String?
    /// Transmit rate in Mb/s.
    var transmitRate: Double
    /// "Wi‑Fi 6" etc.
    var standard: String?
    /// "WPA3 Personal" etc. (nil = unknown).
    var security: String?
    var isSecure: Bool

    /// 0…3 bars, like the menu bar Wi‑Fi icon.
    var bars: Int {
        guard isAssociated else { return 0 }
        switch rssi {
        case (-60)...: return 3
        case (-70)...: return 2
        default:       return 1
        }
    }
}

struct NetworkSample: Hashable, Sendable {
    var date: Date
    /// Bytes per second.
    var download: Double
    var upload: Double
}

/// Everything the widget shows, in one value (also used by DEBUG previews with sample data).
struct NetworkSnapshot: Hashable, Sendable {
    var interface: NetworkInterfaceInfo?
    /// `interface` is the system's primary interface.
    var isPrimary: Bool = true
    var router: String?
    var wifi: WiFiInfo?
    var vpnInterfaces: [String] = []
    var download: Double = 0
    var upload: Double = 0
    var publicIP: String?
    var publicIPFailed = false

    var isConnected: Bool { interface?.hasRoutableAddress == true }
    var vpnActive: Bool { !vpnInterfaces.isEmpty }
}

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// All interfaces that are up and have an address (for the settings' interface picker).
    private(set) var interfaces: [NetworkInterfaceInfo] = []
    private(set) var primaryInterfaceName: String?
    /// The interface Automatic shows: the primary one, or — when the primary interface is a VPN
    /// tunnel (full-tunnel VPN / exit node) — the first physical interface in the service order
    /// that carries the tunnel, so the widget still shows the Wi‑Fi / Ethernet link with a VPN badge.
    private(set) var defaultInterfaceName: String?
    /// Router of `defaultInterfaceName`.
    private(set) var router: String?
    private(set) var wifi: WiFiInfo?
    private(set) var vpnInterfaces: [String] = []
    /// Throughput of the shown interface, oldest first, at most `historySeconds` old.
    private(set) var history: [NetworkSample] = []
    private(set) var download: Double = 0
    private(set) var upload: Double = 0
    private(set) var publicIP: String?
    private(set) var publicIPFailed = false
    private(set) var lastDetailsRefresh: Date?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    /// Throughput is sampled while the widget is in the Nook or a Network view is visible.
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(.network, label: "Network",
                                      onNeeded: { [unowned self] in self.startSampling() },
                                      onIdle: { [unowned self] in self.stopSampling() })
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in self.samplingTask != nil }
        #endif
        return presence
    }()
    @ObservationIgnored private var lastCounters: [String: InterfaceCounters] = [:]
    @ObservationIgnored private var lastCounterDate: Date?
    @ObservationIgnored private var historyInterface: String?
    @ObservationIgnored private var refreshingDetails = false
    @ObservationIgnored private var publicIPTask: Task<Void, Never>?
    @ObservationIgnored private var publicIPKey: String?
    @ObservationIgnored private var publicIPDate: Date?

    static let detailsRefreshInterval: TimeInterval = 3
    /// While no widget is visible: interfaces only (no CoreWLAN), so the sampled interface follows
    /// a change of the primary interface.
    static let hiddenDetailsRefreshInterval: TimeInterval = 30
    static let publicIPRefreshInterval: TimeInterval = 600

    private init() {}

    private var settings: NetworkWidgetSettings { SettingsStore[.networkWidgetSettings] }

    /// The interface the widget shows: the chosen one if it is present, else the primary one.
    var shownInterfaceName: String? {
        if let name = settings.interfaceName, interfaces.contains(where: { $0.bsdName == name }) { return name }
        return defaultInterfaceName ?? primaryInterfaceName
            ?? interfaces.first(where: { $0.kind != .tunnel && $0.hasRoutableAddress })?.bsdName
    }

    var snapshot: NetworkSnapshot {
        let name = shownInterfaceName
        let iface = interfaces.first { $0.bsdName == name }
        return NetworkSnapshot(
            interface: iface,
            isPrimary: name == defaultInterfaceName,
            router: name == defaultInterfaceName ? router : nil,
            // also while nothing is connected, so the empty state can say "Wi‑Fi is turned off"
            // (a powered-off en0 has no address and never becomes `iface`)
            wifi: iface?.kind == .wifi || iface?.hasRoutableAddress != true ? wifi : nil,
            vpnInterfaces: vpnInterfaces,
            download: download, upload: upload,
            publicIP: settings.showsPublicIP ? publicIP : nil,
            publicIPFailed: settings.showsPublicIP && publicIPFailed
        )
    }

    // MARK: - Lifecycle

    /// Follows the settings (idempotent): samples throughput while the widget is in the Nook.
    func start() {
        guard !started else { return }
        started = true
        presence.activate()
        settingsTask = Task { @MainActor [weak self] in
            for await _ in SettingsStore.updates(.networkWidgetSettings, initial: false) {
                self?.settingsChanged()
            }
        }
    }

    /// A Network widget appeared (true) or disappeared (false). Details refresh only while visible;
    /// when the last visible view goes away (e.g. the settings pane closed while the widget is not
    /// in the Nook), sampling stops unless the Nook still holds the widget.
    func setVisible(_ visible: Bool) {
        start()
        presence.setVisible(visible)
        if visible { refreshDetails(force: true) }
    }

    private var isVisible: Bool { presence.isVisible }

    private func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
        lastCounters = [:]
        lastCounterDate = nil
        forgetPublicIPLookup()
    }

    /// Cancels a pending lookup and forgets its key / date: a cancelled lookup must not leave them
    /// behind, or the next visible (or turning the option back on within the refresh interval)
    /// would skip the fetch (stuck at "…").
    private func forgetPublicIPLookup() {
        publicIPTask?.cancel()
        publicIPTask = nil
        publicIPKey = nil
        publicIPDate = nil
    }

    /// The widget's settings changed.
    private func settingsChanged() {
        if samplingTask != nil {
            // interval / interface / history length changed: restart so the new interval applies now
            samplingTask?.cancel()
            samplingTask = nil
            startSampling()
        }
        if !settings.showsPublicIP { forgetPublicIPLookup() }
        if isVisible { refreshDetails(force: true) }
    }

    private func startSampling() {
        guard samplingTask == nil else { return }
        samplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.presence.debugCheckTick("sampling")
                self?.sampleThroughput()
                let interval = Double(self?.settings.samplingInterval ?? 1)
                try? await Task.sleep(for: .seconds(max(1, interval)))
            }
        }
    }

    // MARK: - Throughput

    private func sampleThroughput() {
        let now = Date()
        let counters = Self.readCounters()
        // interface list for the first samples (before any details refresh)
        let sinceDetails = now.timeIntervalSince(lastDetailsRefresh ?? .distantPast)
        if interfaces.isEmpty || sinceDetails >= (isVisible ? Self.detailsRefreshInterval : Self.hiddenDetailsRefreshInterval) {
            refreshDetails(force: false)
        }
        let name = shownInterfaceName
        if name != historyInterface {
            history.removeAll()
            historyInterface = name
        }
        if let name, let previous = lastCounters[name], let current = counters[name], let lastDate = lastCounterDate {
            let dt = now.timeIntervalSince(lastDate)
            if dt > 0.2 {
                // a counter that went backwards (interface reset) counts as no traffic
                let rx = current.received >= previous.received ? Double(current.received - previous.received) : 0
                let tx = current.sent >= previous.sent ? Double(current.sent - previous.sent) : 0
                download = rx / dt
                upload = tx / dt
                history.append(NetworkSample(date: now, download: download, upload: upload))
            }
        } else {
            download = 0
            upload = 0
        }
        let cutoff = now.addingTimeInterval(-Double(settings.historySeconds) - Double(settings.samplingInterval))
        if let first = history.firstIndex(where: { $0.date >= cutoff }), first > 0 {
            history.removeFirst(first)
        }
        lastCounters = counters
        lastCounterDate = now
        for i in interfaces.indices {
            if let speed = counters[interfaces[i].bsdName]?.baudRate, speed > 0, interfaces[i].linkSpeed != speed {
                interfaces[i].linkSpeed = speed
            }
        }
    }

    struct InterfaceCounters: Sendable {
        var received: UInt64
        var sent: UInt64
        var baudRate: UInt64
    }

    /// 64-bit byte counters per interface (sysctl NET_RT_IFLIST2).
    nonisolated static func readCounters() -> [String: InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        length += 512   // interfaces can appear between the two calls
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }
        var result: [String: InterfaceCounters] = [:]
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                let message = base + offset
                let messageLength = Int(message.loadUnaligned(as: UInt16.self))   // ifm_msglen
                guard messageLength > 0, offset + messageLength <= length else { break }
                let type = message.loadUnaligned(fromByteOffset: 3, as: UInt8.self)   // ifm_type
                if Int32(type) == RTM_IFINFO2, messageLength >= MemoryLayout<if_msghdr2>.size {
                    let header = message.loadUnaligned(as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(header.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        result[name] = InterfaceCounters(received: header.ifm_data.ifi_ibytes,
                                                         sent: header.ifm_data.ifi_obytes,
                                                         baudRate: header.ifm_data.ifi_baudrate)
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    // MARK: - Details

    private func refreshDetails(force: Bool) {
        guard !refreshingDetails else { return }
        if !force, let last = lastDetailsRefresh, Date().timeIntervalSince(last) < 1 { return }
        refreshingDetails = true
        let wantsWiFi = isVisible
        Task { @MainActor [weak self] in
            let details = await Task.detached(priority: .utility) { Self.collectDetails(includeWiFi: wantsWiFi) }.value
            guard let self else { return }
            self.refreshingDetails = false
            self.lastDetailsRefresh = Date()
            // keep the link speeds the counters reported
            var interfaces = details.interfaces
            for i in interfaces.indices {
                if let old = self.interfaces.first(where: { $0.bsdName == interfaces[i].bsdName }), interfaces[i].linkSpeed == 0 {
                    interfaces[i].linkSpeed = old.linkSpeed
                }
            }
            if self.interfaces != interfaces { self.interfaces = interfaces }
            if self.primaryInterfaceName != details.primary { self.primaryInterfaceName = details.primary }
            if self.defaultInterfaceName != details.defaultInterface { self.defaultInterfaceName = details.defaultInterface }
            if self.router != details.router { self.router = details.router }
            if wantsWiFi, self.wifi != details.wifi { self.wifi = details.wifi }
            if self.vpnInterfaces != details.vpn { self.vpnInterfaces = details.vpn }
            self.updatePublicIPIfNeeded()
        }
    }

    struct Details: Sendable {
        var interfaces: [NetworkInterfaceInfo]
        var primary: String?
        var defaultInterface: String?
        var router: String?
        var wifi: WiFiInfo?
        var vpn: [String]
    }

    nonisolated static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg", "gif", "stf"]

    nonisolated static func isTunnel(_ name: String) -> Bool {
        // gif / stf are IPv6 transition pseudo-interfaces, not VPNs; they are still not "real" links
        tunnelPrefixes.contains { name.hasPrefix($0) }
    }

    nonisolated static func collectDetails(includeWiFi: Bool) -> Details {
        // addresses (getifaddrs)
        struct Entry { var up = false; var v4: [String] = []; var v6: [String] = [] }
        var entries: [String: Entry] = [:]
        var order: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifap) == 0, let first = ifap {
            defer { freeifaddrs(ifap) }
            for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
                let ifa = pointer.pointee
                let name = String(cString: ifa.ifa_name)
                if entries[name] == nil { entries[name] = Entry(); order.append(name) }
                let flags = Int32(ifa.ifa_flags)
                if flags & IFF_UP != 0 && flags & IFF_RUNNING != 0 { entries[name]?.up = true }
                guard flags & IFF_LOOPBACK == 0, let addr = ifa.ifa_addr else { continue }
                let family = Int32(addr.pointee.sa_family)
                guard family == AF_INET || family == AF_INET6 else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
                guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
                var text = String(cString: host)
                if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
                if family == AF_INET {
                    entries[name]?.v4.append(text)
                } else if !text.lowercased().hasPrefix("fe80") {
                    entries[name]?.v6.append(text)
                }
            }
        }

        // display names and types (SystemConfiguration)
        var displayNames: [String: String] = [:]
        var wifiNames = Set<String>()
        var ethernetNames = Set<String>()
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in all {
                guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
                if let display = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? { displayNames[bsd] = display }
                if let type = SCNetworkInterfaceGetInterfaceType(iface) {
                    if type == kSCNetworkInterfaceTypeIEEE80211 { wifiNames.insert(bsd) }
                    else if type == kSCNetworkInterfaceTypeEthernet || type == kSCNetworkInterfaceTypeBond
                                || type == kSCNetworkInterfaceTypeVLAN { ethernetNames.insert(bsd) }
                }
            }
        }
        let wifiClient = CWWiFiClient.shared()
        for name in wifiClient.interfaceNames() ?? [] { wifiNames.insert(name) }

        var interfaces: [NetworkInterfaceInfo] = []
        for name in order {
            guard let entry = entries[name], entry.up, !(entry.v4.isEmpty && entry.v6.isEmpty) else { continue }
            if name.hasPrefix("lo") || name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("anpi") { continue }
            let kind: NetworkInterfaceInfo.Kind = wifiNames.contains(name) ? .wifi
                : isTunnel(name) ? .tunnel
                : ethernetNames.contains(name) || name.hasPrefix("en") ? .ethernet : .other
            if kind == .tunnel, entry.v4.isEmpty, entry.v6.isEmpty { continue }
            interfaces.append(NetworkInterfaceInfo(
                bsdName: name,
                displayName: displayNames[name] ?? (kind == .wifi ? "Wi‑Fi" : kind == .tunnel ? "VPN" : name),
                kind: kind, isUp: true, ipv4: entry.v4, ipv6: entry.v6, linkSpeed: 0))
        }

        // primary interface + router
        var primary: String?
        var router: String?
        let store = SCDynamicStoreCreate(nil, "DynamicNotch.NetworkWidget" as CFString, nil, nil)
        if let store {
            for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
                if let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                   let name = dict["PrimaryInterface"] as? String {
                    primary = name
                    router = dict["Router"] as? String
                    break
                }
            }
        }

        // primary is a tunnel: the first connected physical interface in the service order
        var defaultInterface = primary
        if let tunnel = primary, isTunnel(tunnel) {
            defaultInterface = nil
            router = nil
            let connected = Set(interfaces.filter { $0.kind != .tunnel && $0.hasRoutableAddress }.map(\.bsdName))
            for (serviceID, bsd) in orderedServices() where connected.contains(bsd) {
                defaultInterface = bsd
                if let store,
                   let dict = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(serviceID)/IPv4" as CFString) as? [String: Any] {
                    router = dict["Router"] as? String
                }
                break
            }
            if defaultInterface == nil {
                defaultInterface = interfaces.first { $0.kind != .tunnel && $0.hasRoutableAddress }?.bsdName ?? tunnel
            }
        }

        // VPN presence
        var vpn = Set<String>()
        if let primary, isTunnel(primary) { vpn.insert(primary) }
        if let proxies = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
           let scoped = proxies["__SCOPED__"] as? [String: Any] {
            for name in scoped.keys where isTunnel(name) && !name.hasPrefix("gif") && !name.hasPrefix("stf") { vpn.insert(name) }
        }
        for iface in interfaces where iface.kind == .tunnel
            && iface.ipv4.contains(where: { !$0.hasPrefix("169.254.") }) && !iface.bsdName.hasPrefix("gif") {
            vpn.insert(iface.bsdName)
        }

        // Wi‑Fi
        var wifi: WiFiInfo?
        if includeWiFi, let iface = wifiClient.interface() {
            let rssi = iface.rssiValue()
            let channel = iface.wlanChannel()
            let associated = rssi != 0 || channel != nil
            wifi = WiFiInfo(
                ssid: iface.ssid(),
                isPoweredOn: iface.powerOn(),
                isAssociated: associated,
                rssi: rssi,
                noise: iface.noiseMeasurement(),
                channel: channel.map { $0.channelNumber },
                band: channel.flatMap { bandName($0.channelBand) },
                transmitRate: iface.transmitRate(),
                standard: standardName(iface.activePHYMode()),
                security: securityName(iface.security()),
                isSecure: ![CWSecurity.none, .unknown].contains(iface.security()))
        }

        return Details(interfaces: interfaces, primary: primary, defaultInterface: defaultInterface,
                       router: router, wifi: wifi, vpn: vpn.sorted())
    }

    /// (service ID, BSD name) of the current network set's services in the user's service order
    /// (System Settings ▸ Network ▸ Set Service Order).
    nonisolated private static func orderedServices() -> [(String, String)] {
        guard let prefs = SCPreferencesCreate(nil, "DynamicNotch.NetworkWidget" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService]
        else { return [] }
        var byID: [String: String] = [:]
        for service in services where SCNetworkServiceGetEnabled(service) {
            guard let id = SCNetworkServiceGetServiceID(service) as String?,
                  let iface = SCNetworkServiceGetInterface(service),
                  let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
            byID[id] = bsd
        }
        let order = (SCNetworkSetGetServiceOrder(set) as? [String]) ?? Array(byID.keys)
        return order.compactMap { id in byID[id].map { (id, $0) } }
    }

    nonisolated private static func bandName(_ band: CWChannelBand) -> String? {
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default:        return nil
        }
    }

    nonisolated private static func standardName(_ mode: CWPHYMode) -> String? {
        switch mode {
        case .mode11ax: return "Wi‑Fi 6"
        case .mode11ac: return "Wi‑Fi 5"
        case .mode11n:  return "Wi‑Fi 4"
        case .mode11a, .mode11b, .mode11g: return "802.11" + (mode == .mode11a ? "a" : mode == .mode11b ? "b" : "g")
        default:
            // Wi‑Fi 7 (802.11be) has no CWPHYMode case name in older SDKs
            return mode.rawValue == 7 ? "Wi‑Fi 7" : nil
        }
    }

    nonisolated private static func securityName(_ security: CWSecurity) -> String? {
        switch security {
        case .none: return "Open"
        case .WEP, .dynamicWEP: return "WEP"
        case .wpaPersonal, .wpaPersonalMixed: return "WPA Personal"
        case .wpa2Personal, .personal: return "WPA2 Personal"
        case .wpa3Personal: return "WPA3 Personal"
        case .wpa3Transition: return "WPA2/WPA3 Personal"
        case .wpaEnterprise, .wpaEnterpriseMixed: return "WPA Enterprise"
        case .wpa2Enterprise, .enterprise: return "WPA2 Enterprise"
        case .wpa3Enterprise: return "WPA3 Enterprise"
        case .OWE, .oweTransition: return "Enhanced Open"
        default: return nil
        }
    }

    // MARK: - Public IP

    private func updatePublicIPIfNeeded() {
        guard settings.showsPublicIP, isVisible else { return }
        let key = "\(primaryInterfaceName ?? "-")|\(vpnInterfaces.joined(separator: ","))|\(router ?? "-")"
        let stale = publicIPDate.map { Date().timeIntervalSince($0) > Self.publicIPRefreshInterval } ?? true
        guard key != publicIPKey || stale, publicIPTask == nil else { return }
        publicIPKey = key
        publicIPDate = Date()
        guard primaryInterfaceName != nil else { publicIP = nil; return }
        publicIPTask = Task { @MainActor [weak self] in
            let address = await Self.fetchPublicIP()
            guard let self, !Task.isCancelled else { return }
            self.publicIPTask = nil
            self.publicIP = address
            self.publicIPFailed = address == nil
        }
    }

    /// Forces a new lookup (settings ▸ Refresh).
    func refreshPublicIP() {
        publicIPKey = nil
        publicIPDate = nil
        publicIPTask?.cancel()
        publicIPTask = nil
        updatePublicIPIfNeeded()
    }

    nonisolated static func fetchPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 45,
              text.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == ":" })
        else { return nil }
        return text
    }
}
