// Mounted volumes and their capacity for the Storage widget (2026-10-20).
// FileManager.mountedVolumeURLs (hidden volumes skipped, so the APFS /System/Volumes/* system,
// data, VM and preboot volumes are left out; "/" stands for the startup disk) + URLResourceValues.
// Refreshes every 60 s while started and immediately on NSWorkspace mount / unmount / rename.
// Runs while a Storage view is visible or the widget is in the Nook (WidgetPresence); otherwise it
// stops (when the last view disappears or the widget is removed from the Nook).
// Reading runs on a dedicated serial queue, one read at a time: a stalled network volume blocks
// neither the UI nor Swift concurrency's cooperative pool, and reads do not pile up behind it.
import Foundation
import AppKit
import Observation
import DiskArbitration

struct StorageVolume: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case internalDisk, external, diskImage, optical, network

        var systemImage: String {
            switch self {
            case .internalDisk: return "internaldrive"
            case .external:     return "externaldrive"
            case .diskImage:    return "externaldrive"     // no dedicated SF Symbol; Finder uses a drive too
            case .optical:      return "opticaldisc"
            case .network:      return "network"
            }
        }
    }

    /// Volume UUID when known, else the mount path.
    var id: String
    var name: String
    var url: URL
    var kind: Kind
    var totalBytes: Int64
    var availableBytes: Int64
    /// Can be ejected / unmounted from the widget (removable, ejectable or network volume).
    var isEjectable: Bool

    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }
    var usedFraction: Double { totalBytes > 0 ? min(max(Double(usedBytes) / Double(totalBytes), 0), 1) : 0 }
    var usedPercent: Int { Int((usedFraction * 100).rounded()) }
}

@MainActor
@Observable
final class StorageVolumesManager {
    static let shared = StorageVolumesManager()

    private(set) var volumes: [StorageVolume] = []
    private(set) var lastRefresh: Date?
    /// Last eject failure (volume name + message). Cleared when it is tapped, when the next eject
    /// starts, or by a refresh once the volume it is about is no longer mounted or the error is
    /// older than `refreshInterval`.
    private(set) var ejectError: String?
    /// Volumes being ejected (their button shows progress).
    private(set) var ejecting: Set<String> = []

    static let refreshInterval: TimeInterval = 60

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Runs while a Storage view is visible or the widget is in the Nook.
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(.storage, label: "Storage",
                                      onNeeded: { [unowned self] in self.install() },
                                      onIdle: { [unowned self] in self.tearDown() })
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in self.timer != nil || !self.observers.isEmpty }
        #endif
        return presence
    }()
    /// A read is running on `readQueue`; further refreshes are coalesced into one follow-up.
    @ObservationIgnored private var readInFlight = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var ejectErrorVolumeID: String?
    @ObservationIgnored private var ejectErrorDate: Date?

    nonisolated private static let readQueue = DispatchQueue(label: "StorageVolumesManager.read", qos: .utility)

    private init() {}

    /// A Storage view appeared (true) or disappeared (false).
    func setVisible(_ visible: Bool) {
        presence.setVisible(visible)
    }

    /// Starts monitoring (idempotent) without a visible view (DEBUG hooks): it stops again at the
    /// latest one refresh interval later unless a view is visible or the widget is in the Nook.
    func start() {
        presence.touch(holdFor: Self.refreshInterval)
    }

    /// Removes the timer and the mount observers now. `volumes` keeps the last values.
    func stop() {
        presence.forceIdle()
    }

    private func install() {
        guard timer == nil else { return }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        let t = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.presence.debugCheckTick()
                self.refresh()
            }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
        refreshAgain = false
    }

    func refresh() {
        guard !readInFlight else { refreshAgain = true; return }
        readInFlight = true
        Self.readQueue.async {
            let list = Self.readVolumes()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finishRefresh(list) }
            }
        }
    }

    private func finishRefresh(_ list: [StorageVolume]) {
        readInFlight = false
        volumes = list
        lastRefresh = Date()
        if ejectError != nil {
            // the volume the error was about is gone (ejected later, e.g. from Finder), or the
            // message has been up for a full refresh interval
            let gone = ejectErrorVolumeID.map { id in !list.contains { $0.id == id } } ?? true
            let old = ejectErrorDate.map { Date().timeIntervalSince($0) >= Self.refreshInterval } ?? true
            if gone || old { dismissEjectError() }
        }
        if refreshAgain {
            refreshAgain = false
            refresh()
        }
    }

    func eject(_ volume: StorageVolume) {
        guard !ejecting.contains(volume.id) else { return }
        ejecting.insert(volume.id)
        dismissEjectError()
        let url = volume.url
        let name = volume.name
        let id = volume.id
        // a blocking call (a busy or stalled volume): a GCD thread, not the cooperative pool
        DispatchQueue.global(qos: .userInitiated).async {
            let failure: String?
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.ejecting.remove(id)
                    if let failure {
                        self.ejectError = "\(name): \(failure)"
                        self.ejectErrorVolumeID = id
                        self.ejectErrorDate = Date()
                    }
                    self.refresh()
                }
            }
        }
    }

    func dismissEjectError() {
        ejectError = nil
        ejectErrorVolumeID = nil
        ejectErrorDate = nil
    }

    // MARK: - Reading

    nonisolated private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeUUIDStringKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsLocalKey,
        .volumeIsBrowsableKey, .volumeIsRootFileSystemKey, .volumeLocalizedFormatDescriptionKey,
    ]

    nonisolated static func readVolumes() -> [StorageVolume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var result: [StorageVolume] = []
        var seen = Set<String>()
        let session = DASessionCreate(kCFAllocatorDefault)
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.volumeIsBrowsable == false { continue }
            let path = url.path
            // APFS system companions (skipHiddenVolumes normally hides them)
            if path.hasPrefix("/System/Volumes/") || path == "/private/var/vm" { continue }
            guard let total = v.volumeTotalCapacity, total > 0 else { continue }
            let important = v.volumeAvailableCapacityForImportantUsage ?? 0
            let available = important > 0 ? important : Int64(v.volumeAvailableCapacity ?? 0)
            let isRoot = v.volumeIsRootFileSystem == true || path == "/"
            let kind = classify(v, url: url, isRoot: isRoot, session: session)
            let id = v.volumeUUIDString ?? path
            guard seen.insert(id).inserted else { continue }
            let name = v.volumeLocalizedName ?? v.volumeName ?? url.lastPathComponent
            let ejectable = !isRoot && (v.volumeIsRemovable == true || v.volumeIsEjectable == true || kind == .network
                                        || kind == .diskImage || kind == .external)
            result.append(StorageVolume(id: id, name: name, url: url, kind: kind, totalBytes: Int64(total),
                                        availableBytes: available, isEjectable: ejectable))
        }
        // startup disk first, then internal, external, images, optical, network; by name within
        let order: [StorageVolume.Kind] = [.internalDisk, .external, .diskImage, .optical, .network]
        return result.sorted { a, b in
            if (a.url.path == "/") != (b.url.path == "/") { return a.url.path == "/" }
            let ia = order.firstIndex(of: a.kind) ?? 0, ib = order.firstIndex(of: b.kind) ?? 0
            if ia != ib { return ia < ib }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    nonisolated private static func classify(_ v: URLResourceValues, url: URL, isRoot: Bool, session: DASession?) -> StorageVolume.Kind {
        if isRoot { return .internalDisk }
        if v.volumeIsLocal == false { return .network }
        // DiskArbitration tells disk images and optical media apart (URLResourceValues report both

        if let session, let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
           let desc = DADiskCopyDescription(disk) as? [String: Any] {
            let model = (desc[kDADiskDescriptionDeviceModelKey as String] as? String ?? "")
                .trimmingCharacters(in: .whitespaces)
            let media = desc[kDADiskDescriptionMediaKindKey as String] as? String ?? ""
            let proto = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
            if model == "Disk Image" || proto == "Disk Image" { return .diskImage }
            if ["IOCDMedia", "IODVDMedia", "IOBDMedia"].contains(media) { return .optical }
            if desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool == true,
               v.volumeIsRemovable != true { return .internalDisk }
            return .external
        }
        if v.volumeIsInternal == true && v.volumeIsRemovable != true { return .internalDisk }
        return .external
    }
}
