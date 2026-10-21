// F8: folder watcher of the Downloads widget (2026-10-20).
//
// Watches one folder (Settings ▸ Widgets ▸ Downloads; default ~/Downloads) and lists its newest
// top-level items (`addedToDirectoryDate`, else creation / modification date):
//   - changes: a DispatchSource (vnode: write / rename / delete / link / attrib) on the folder,
//     debounced, re-reads the listing on a serial utility queue (never on the main thread or the
//     cooperative pool; a slow network folder blocks neither);
//   - downloads in progress: Safari `name.download` bundles (the partial file inside; byte counts
//     from the bundle's Info.plist when present), Chrome / Edge / Arc `.crdownload`, Firefox
//     `.part` (its zero-byte placeholder is hidden), and any file for which another app publishes
//     an NSProgress (`Progress.addSubscriber(forFileURL:)` on the folder: Safari, Chrome and
//     Finder copies publish one, which gives a determinate fraction). While one is in progress the
//     folder is re-read every second for size growth (rate) — the vnode source does not fire for
//     writes inside files. A partial file that has not grown for `stallInterval` and has no
//     published progress counts as stopped (an abandoned download), not as in progress;
//   - "Clear Old": items added more than `clearAfterDays` ago go to the Trash
//     (NSWorkspace.recycle, undoable from the Trash) after a confirmation in the widget; with
//     `autoClear` (opt-in, confirmed in Settings) at most every `autoClearInterval`. Hidden files and
//     downloads in progress are never cleared.
// Lifecycle (WidgetPresence): runs while a Downloads view is visible or the widget is in the Nook
// (the closed-notch progress indicator needs it then); otherwise the source, the progress
// subscription and the timers are torn down at once. `activate()` (AppDelegate, at launch) starts
// following the Nook layout and the widget's settings.
import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers

struct DownloadItem: Identifiable, Hashable, Sendable {
    /// A browser's partial-download format.
    enum Partial: String, Hashable, Sendable {
        case safari     // name.download bundle
        case chromium   // name.crdownload
        case firefox    // name.part
    }

    var url: URL
    /// Display name: the partial extension removed ("file.zip" for "file.zip.crdownload").
    var name: String
    /// Bytes (directories: summed, capped); nil when unknown.
    var size: Int64?
    /// When the item arrived in the folder.
    var added: Date
    /// Last write (Safari: the partial file inside the bundle).
    var modified: Date
    var isDirectory: Bool
    var isPackage: Bool
    var partial: Partial?
    /// Safari's Info.plist: bytes received / expected (when present).
    var expectedBytes: Int64?
    var receivedBytes: Int64?
    /// The file being written (Safari: inside the bundle), for progress matching.
    var dataURL: URL?

    var id: String { url.path }
    var finalExtension: String { (name as NSString).pathExtension.lowercased() }
    /// Where the finished download will be (progress published by a browser may use this path).
    var finalURL: URL { url.deletingLastPathComponent().appendingPathComponent(name) }
}

/// Progress of one download in progress.
struct DownloadProgress: Equatable, Sendable {
    /// 0…1, nil = indeterminate (size growth only).
    var fraction: Double?
    var bytes: Int64
    var totalBytes: Int64?
    var bytesPerSecond: Double?
    /// Not growing and no published progress: abandoned / paused.
    var isStalled: Bool
}

@MainActor
@Observable
final class DownloadsWatcher {
    static let shared = DownloadsWatcher()

    enum FolderStatus: Equatable, Sendable {
        case unknown, ok, missing, notFolder, denied
    }

    struct ClearPlan: Equatable {
        var urls: [URL]
        var bytes: Int64
        var days: Int
    }

    /// Newest items (in progress first), at most `itemCount`.
    private(set) var items: [DownloadItem] = []
    /// Items in the folder (after the hidden-file filter).
    private(set) var totalCount = 0
    private(set) var status: FolderStatus = .unknown
    private(set) var lastScan: Date?
    /// Progress per in-progress item (keyed by `DownloadItem.id`).
    private(set) var progress: [String: DownloadProgress] = [:]
    /// A download is in progress and not stalled (drives the closed-notch indicator; changes only
    /// when the answer changes, so NotchView does not re-render on every progress tick).
    private(set) var hasActiveDownloads = false
    /// Combined progress of the active downloads (closed-notch indicator).
    private(set) var combinedProgress: DownloadProgress?
    private(set) var activeCount = 0
    /// `hasActiveDownloads` and "Show progress in the closed notch" is on (observed by the
    /// closed-notch indicator; SettingsStore reads are not observable).
    private(set) var wantsClosedNotchIndicator = false

    // Clear Old
    private(set) var clearPlan: ClearPlan?
    private(set) var isPreparingClear = false
    private(set) var isClearing = false
    /// Result / error of the last clear (shown once in the widget).
    private(set) var clearMessage: String?

    nonisolated static let stallInterval: TimeInterval = 60
    static let autoClearInterval: TimeInterval = 6 * 3600
    nonisolated static let scanQueue = DispatchQueue(label: "DownloadsWatcher.scan", qos: .utility)
    private static let lastAutoClearKey = "downloadsWidget.lastAutoClear"

    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var progressSubscriber: Any?
    /// Published progress per resolved file path.
    @ObservationIgnored private var published: [String: Progress] = [:]
    @ObservationIgnored private var publishedObservations: [String: NSKeyValueObservation] = [:]
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var debounce: DispatchWorkItem?
    @ObservationIgnored private var progressRecompute: DispatchWorkItem?
    @ObservationIgnored private var retryWork: DispatchWorkItem?
    @ObservationIgnored private var scanInFlight = false
    @ObservationIgnored private var scanAgain = false
    @ObservationIgnored private var generation = 0
    /// Last (bytes, time, smoothed rate) per in-progress item.
    @ObservationIgnored private var rateHistory: [String: (bytes: Int64, time: Date, rate: Double?)] = [:]
    /// Summed sizes of the listed folders, reused while a folder's modification date is unchanged
    /// (the 1 s poll during a download must not walk every listed folder again).
    @ObservationIgnored private var directorySizes: [String: CachedDirectorySize] = [:]
    /// When each published progress last moved (a publisher that died without unpublishing must
    /// not keep the 1 s poll running).
    @ObservationIgnored private var publishedChanged: [String: Date] = [:]
    /// Bumped whenever a pending Clear Old plan is withdrawn (cancel, folder change, tear-down), so a
    /// plan still being prepared is dropped when it arrives.
    @ObservationIgnored private var clearToken = 0
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    /// Runs while a Downloads view is visible or the widget is in the Nook.
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(.downloads, label: "Downloads",
                                      onNeeded: { [unowned self] in self.install() },
                                      onIdle: { [unowned self] in self.tearDown() })
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in self.folder != nil || self.pollTimer != nil }
        #endif
        return presence
    }()
    @ObservationIgnored private var appliedSettings = SettingsStore[.downloadsWidgetSettings]

    private init() {}

    var isRunning: Bool { folder != nil }
    var settings: DownloadsWidgetSettings { SettingsStore[.downloadsWidgetSettings] }

    // MARK: lifecycle

    /// Called once at launch: follows the Nook layout (WidgetPresence) and the widget's settings.
    func activate() {
        if settingsTask == nil {
            settingsTask = Task { @MainActor in
                for await value in SettingsStore.updates(.downloadsWidgetSettings, initial: false) {
                    DownloadsWatcher.shared.apply(value)
                }
            }
        }
        presence.activate()
    }

    /// A Downloads view (widget / settings pane) appeared (true) or disappeared (false).
    func setVisible(_ visible: Bool) {
        presence.setVisible(visible)
    }

    /// Runs the watcher without a visible view for `seconds` (DEBUG hooks); it stops again
    /// afterwards unless a view is visible or the widget is in the Nook.
    func start(holdFor seconds: TimeInterval = 10) {
        presence.touch(holdFor: seconds)
    }

    /// Tears everything down now (the next visibility / layout change applies the state again).
    func stop() {
        presence.forceIdle()
    }

    private func apply(_ value: DownloadsWidgetSettings) {
        let previous = appliedSettings
        appliedSettings = value
        updateIndicator()
        guard isRunning else { return }
        if value.folderURL != previous.folderURL {
            tearDown()
            items = []
            totalCount = 0
            status = .unknown
            withdrawClearPlan()
            directorySizes.removeAll()
            install()
        } else if value != previous {
            if value.autoClear && !previous.autoClear {
                // turned on just now (confirmed in Settings): clear on this scan
                UserDefaults.standard.removeObject(forKey: Self.lastAutoClearKey)
            }
            scheduleScan(after: 0)
        }
    }

    /// Starts watching (idempotent; WidgetPresence `onNeeded`).
    private func install() {
        guard folder == nil else { return }
        let url = settings.folderURL.resolvingSymlinksInPath().standardizedFileURL
        folder = url
        appliedSettings = settings
        generation += 1
        installSource(for: url)
        installProgressSubscriber(for: url)
        scheduleScan(after: 0)
    }

    /// Tears everything down (WidgetPresence `onIdle`). `items` keeps the last listing (the next
    /// install re-reads it).
    private func tearDown() {
        guard folder != nil else { return }
        folder = nil
        generation += 1
        source?.cancel()
        source = nil
        if let progressSubscriber { Progress.removeSubscriber(progressSubscriber) }
        progressSubscriber = nil
        publishedObservations.values.forEach { $0.invalidate() }
        publishedObservations.removeAll()
        published.removeAll()
        publishedChanged.removeAll()
        withdrawClearPlan()
        pollTimer?.invalidate()
        pollTimer = nil
        debounce?.cancel()
        debounce = nil
        progressRecompute?.cancel()
        progressRecompute = nil
        retryWork?.cancel()
        retryWork = nil
        scanAgain = false
        rateHistory.removeAll()
        if !progress.isEmpty { progress = [:] }
        setActive(nil, count: 0)
    }

    // MARK: folder source

    private func installSource(for url: URL) {
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // missing / no permission: the scan reports why; try again later (a folder that is
            // created or allowed later is picked up)
            scheduleRetry()
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link, .attrib, .extend, .revoke],
            queue: Self.scanQueue)
        let gen = generation
        src.setEventHandler { [weak src] in
            let events = src?.data ?? []
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DownloadsWatcher.shared.folderChanged(events, generation: gen) }
            }
        }
        src.setCancelHandler { _ = Darwin.close(fd) }
        src.resume()
        source = src
    }

    private func folderChanged(_ events: DispatchSource.FileSystemEvent, generation gen: Int) {
        guard gen == generation, folder != nil else { return }
        if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
            // the folder itself was moved / deleted: re-open it by path
            source?.cancel()
            source = nil
            scheduleRetry(after: 1)
        }
        scheduleScan(after: 0.25)
    }

    private func scheduleRetry(after delay: TimeInterval = 10) {
        retryWork?.cancel()
        let gen = generation
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                let w = DownloadsWatcher.shared
                w.retryWork = nil
                guard gen == w.generation, let folder = w.folder, w.source == nil else { return }
                w.installSource(for: folder)
                w.scheduleScan(after: 0)
            }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: published progress (NSProgress file subscription)

    private func installProgressSubscriber(for url: URL) {
        let gen = generation
        progressSubscriber = Progress.addSubscriber(forFileURL: url) { progress in
            let fileURL = (progress.userInfo[.fileURLKey] as? URL) ?? progress.fileURL
            guard let fileURL else { return nil }
            let path = Self.resolvedPath(fileURL)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DownloadsWatcher.shared.didPublish(progress, path: path, generation: gen) }
            }
            return {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { DownloadsWatcher.shared.didUnpublish(path: path, generation: gen) }
                }
            }
        }
    }

    private func didPublish(_ p: Progress, path: String, generation gen: Int) {
        guard gen == generation else { return }
        published[path] = p
        publishedChanged[path] = Date()
        publishedObservations[path]?.invalidate()
        publishedObservations[path] = p.observe(\.fractionCompleted, options: []) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let w = DownloadsWatcher.shared
                    guard gen == w.generation else { return }
                    if w.published[path] != nil { w.publishedChanged[path] = Date() }
                    w.scheduleProgressRecompute()
                }
            }
        }
        scheduleScan(after: 0.1)
    }

    private func didUnpublish(path: String, generation gen: Int) {
        guard gen == generation else { return }
        publishedObservations.removeValue(forKey: path)?.invalidate()
        published.removeValue(forKey: path)
        publishedChanged.removeValue(forKey: path)
        scheduleScan(after: 0.25)
    }

    nonisolated static func resolvedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The live progress another app publishes for `item` (finished / cancelled ones are ignored),
    /// and when it last moved.
    private func publishedProgress(for item: DownloadItem) -> (progress: Progress, changed: Date)? {
        for url in [item.url, item.finalURL, item.dataURL].compactMap({ $0 }) {
            let path = Self.resolvedPath(url)
            if let p = published[path], !p.isFinished, !p.isCancelled {
                return (p, publishedChanged[path] ?? .distantPast)
            }
        }
        return nil
    }

    // MARK: scanning

    private func scheduleScan(after delay: TimeInterval) {
        debounce?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { DownloadsWatcher.shared.scan() } }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Re-reads the folder now (coalesced while a read runs).
    func scan() {
        guard let folder else { return }
        guard !scanInFlight else { scanAgain = true; return }
        scanInFlight = true
        let s = settings
        let gen = generation
        let known = directorySizes
        Self.scanQueue.async {
            let result = Self.read(folder: folder, showHidden: s.showHidden, limit: max(s.itemCount, 1), now: Date(),
                                   knownSizes: known)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DownloadsWatcher.shared.finishScan(result, generation: gen) }
            }
        }
    }

    private func finishScan(_ result: ScanResult, generation gen: Int) {
        scanInFlight = false
        defer {
            if scanAgain { scanAgain = false; scan() }
        }
        guard gen == generation else { return }
        directorySizes = result.directorySizes
        if status != result.status { status = result.status }
        if items != result.items { items = result.items }
        if totalCount != result.totalCount { totalCount = result.totalCount }
        lastScan = Date()
        recomputeProgress()
        updatePolling()
        if result.status == .ok, settings.autoClear { autoClearIfDue() }
        // the source could not be opened (folder missing / not allowed) but now reads: watch it
        if result.status == .ok, source == nil, retryWork == nil { scheduleRetry(after: 0) }
    }

    /// Re-reads the folder every second while a listed download is in progress and not stalled
    /// (size growth, stall detection), every 15 s while only stopped partial files are listed (a
    /// resumed download is noticed), not at all otherwise. A published progress that matches no
    /// listed item does not poll (the vnode source / its publication schedule a scan when the file
    /// appears), and one that stopped moving goes stale like a partial file.
    private func updatePolling() {
        let interval = Self.pollInterval(hasActiveDownloads: hasActiveDownloads,
                                         listsPartial: items.contains(where: { $0.partial != nil }))
        guard interval != pollTimer?.timeInterval else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        guard let interval else { return }
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                DownloadsWatcher.shared.presence.debugCheckTick()
                DownloadsWatcher.shared.scan()
            }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    nonisolated static func pollInterval(hasActiveDownloads: Bool, listsPartial: Bool) -> TimeInterval? {
        if hasActiveDownloads { return 1 }
        return listsPartial ? 15 : nil
    }

    private func scheduleProgressRecompute() {
        guard progressRecompute == nil else { return }
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                DownloadsWatcher.shared.progressRecompute = nil
                DownloadsWatcher.shared.recomputeProgress()
            }
        }
        progressRecompute = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func recomputeProgress() {
        let now = Date()
        var next: [String: DownloadProgress] = [:]
        for item in items {
            let published = publishedProgress(for: item)
            let pub = published?.progress
            guard item.partial != nil || pub != nil else { continue }
            let bytes = item.receivedBytes.map { max($0, item.size ?? 0) } ?? item.size ?? 0
            var fraction: Double?
            var total: Int64?
            if let pub, pub.totalUnitCount > 0 {
                fraction = min(max(pub.fractionCompleted, 0), 1)
                total = pub.kind == .file ? pub.totalUnitCount : nil
            } else if let expected = item.expectedBytes, expected > 0 {
                fraction = min(Double(bytes) / Double(expected), 1)
                total = expected
            }
            // rate: exponential moving average of the size growth between scans
            var rate: Double?
            if let last = rateHistory[item.id] {
                let dt = now.timeIntervalSince(last.time)
                if bytes != last.bytes, dt > 0.2 {
                    let instant = Double(max(bytes - last.bytes, 0)) / dt
                    rate = last.rate.map { $0 * 0.6 + instant * 0.4 } ?? instant
                    rateHistory[item.id] = (bytes, now, rate)
                } else if dt <= 5 {
                    rate = last.rate // no growth since the last sample: keep the rate for a few seconds
                }
            } else {
                rateHistory[item.id] = (bytes, now, nil)
            }
            // stalled: the file has not grown for a while and no published progress moved either
            let pubIdle = published.map { now.timeIntervalSince($0.changed) > Self.stallInterval } ?? true
            let stalled = pubIdle && now.timeIntervalSince(item.modified) > Self.stallInterval
            next[item.id] = DownloadProgress(fraction: fraction, bytes: bytes, totalBytes: total,
                                             bytesPerSecond: stalled ? nil : rate, isStalled: stalled)
        }
        rateHistory = rateHistory.filter { next[$0.key] != nil }
        if next != progress { progress = next }

        let active = next.values.filter { !$0.isStalled }
        guard !active.isEmpty else { setActive(nil, count: 0); return }
        let bytes = active.reduce(Int64(0)) { $0 + $1.bytes }
        var fraction: Double?
        if active.allSatisfy({ $0.fraction != nil }) {
            let totals = active.compactMap(\.totalBytes)
            if totals.count == active.count, totals.reduce(0, +) > 0 {
                fraction = Double(bytes) / Double(totals.reduce(0, +))
                fraction = min(max(fraction ?? 0, 0), 1)
            } else {
                fraction = active.compactMap(\.fraction).reduce(0, +) / Double(active.count)
            }
        }
        let rates = active.compactMap(\.bytesPerSecond)
        setActive(DownloadProgress(fraction: fraction, bytes: bytes,
                                   totalBytes: nil, bytesPerSecond: rates.isEmpty ? nil : rates.reduce(0, +),
                                   isStalled: false),
                  count: active.count)
    }

    private func setActive(_ combined: DownloadProgress?, count: Int) {
        let has = combined != nil
        if hasActiveDownloads != has { hasActiveDownloads = has }
        if combinedProgress != combined { combinedProgress = combined }
        if activeCount != count { activeCount = count }
        updateIndicator()
    }

    private func updateIndicator() {
        let wants = hasActiveDownloads && appliedSettings.showInClosedNotch
        if wantsClosedNotchIndicator != wants { wantsClosedNotchIndicator = wants }
    }

    // MARK: reading (scan queue)

    struct ScanResult: Sendable {
        var status: FolderStatus
        var items: [DownloadItem] = []
        var totalCount = 0
        /// Sizes of the listed folders (fed back as `knownSizes` to the next read).
        var directorySizes: [String: CachedDirectorySize] = [:]
    }

    /// A folder's summed size, valid while its modification date is `modified`.
    struct CachedDirectorySize: Equatable, Sendable {
        var modified: Date
        var size: Int64?
    }

    nonisolated static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey, .addedToDirectoryDateKey,
        .creationDateKey, .contentModificationDateKey,
    ]

    /// Names never listed (Finder bookkeeping).
    nonisolated static let ignoredNames: Set<String> = [".DS_Store", ".localized", "Icon\r"]

    nonisolated static func read(folder: URL, showHidden: Bool, limit: Int, now: Date,
                                 knownSizes: [String: CachedDirectorySize] = [:],
                                 measure: (URL) -> Int64? = { directorySize($0) }) -> ScanResult {
        let fm = FileManager()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir) else {
            // exists-but-unreadable also lands here for some TCC-protected paths
            return ScanResult(status: (Darwin.access(folder.path, F_OK) == 0) ? .denied : .missing)
        }
        guard isDir.boolValue else { return ScanResult(status: .notFolder) }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: resourceKeys,
                                              options: showHidden ? [] : [.skipsHiddenFiles])
        } catch {
            return ScanResult(status: isPermissionError(error) ? .denied : .missing)
        }
        var entries = urls.compactMap { entry(for: $0) }
        // Firefox keeps a zero-byte placeholder with the final name next to name.part
        let partNames = Set(entries.filter { $0.partial == .firefox }.map(\.name))
        entries.removeAll { $0.partial == nil && partNames.contains($0.url.lastPathComponent) && ($0.size ?? 0) == 0 }

        // downloads that are still being written first, then newest
        func isFresh(_ e: DownloadItem) -> Bool { e.partial != nil && now.timeIntervalSince(e.modified) <= stallInterval }
        entries.sort { a, b in
            let fa = isFresh(a), fb = isFresh(b)
            if fa != fb { return fa }
            if a.added != b.added { return a.added > b.added }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        var top = Array(entries.prefix(limit))
        var sizes: [String: CachedDirectorySize] = [:]
        for i in top.indices where top[i].isDirectory && top[i].partial == nil {
            let key = top[i].id
            if let cached = knownSizes[key], cached.modified == top[i].modified {
                top[i].size = cached.size
                sizes[key] = cached
            } else {
                let size = measure(top[i].url)
                top[i].size = size
                sizes[key] = CachedDirectorySize(modified: top[i].modified, size: size)
            }
        }
        return ScanResult(status: .ok, items: top, totalCount: entries.count, directorySizes: sizes)
    }

    nonisolated static func entry(for url: URL) -> DownloadItem? {
        let name = url.lastPathComponent
        guard !ignoredNames.contains(name) else { return nil }
        guard let v = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
        let isDirectory = v.isDirectory ?? false
        let modified = v.contentModificationDate ?? v.creationDate ?? .distantPast
        let added = v.addedToDirectoryDate ?? v.creationDate ?? modified
        let ext = url.pathExtension.lowercased()
        var item = DownloadItem(url: url, name: name, size: isDirectory ? nil : v.fileSize.map(Int64.init),
                                added: added, modified: modified, isDirectory: isDirectory,
                                isPackage: v.isPackage ?? false, partial: nil)
        switch ext {
        case "download" where isDirectory:
            item.partial = .safari
            item.name = (name as NSString).deletingPathExtension
            readSafariBundle(into: &item)
        case "crdownload" where !isDirectory:
            item.partial = .chromium
            item.name = (name as NSString).deletingPathExtension
        case "part" where !isDirectory:
            item.partial = .firefox
            item.name = (name as NSString).deletingPathExtension
        default:
            break
        }
        return item
    }

    /// Safari's bundle: the partial file (the largest non-plist child) and Info.plist's byte counts.
    nonisolated static func readSafariBundle(into item: inout DownloadItem) {
        let fm = FileManager()
        let children = (try? fm.contentsOfDirectory(at: item.url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                     options: [.skipsHiddenFiles])) ?? []
        var best: (url: URL, size: Int64, modified: Date?)?
        for child in children where child.lastPathComponent != "Info.plist" {
            let v = try? child.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(v?.fileSize ?? 0)
            if best == nil || size > best!.size { best = (child, size, v?.contentModificationDate) }
        }
        if let best {
            item.dataURL = best.url
            item.size = best.size
            if let m = best.modified, m > item.modified { item.modified = m }
        } else {
            item.size = 0
        }
        let plist = item.url.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: plist),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            func int64(_ key: String) -> Int64? { (dict[key] as? NSNumber)?.int64Value }
            if let total = int64("DownloadEntryProgressTotalToLoad"), total > 0 { item.expectedBytes = total }
            if let received = int64("DownloadEntryProgressBytesSoFar"), received >= 0 { item.receivedBytes = received }
        }
    }

    /// Summed file sizes of a folder / package (stops after `limit` entries: an estimate then).
    nonisolated static func directorySize(_ url: URL, limit: Int = 20_000) -> Int64? {
        guard let e = FileManager().enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                               options: [], errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        var count = 0
        for case let child as URL in e {
            count += 1
            if count > limit { break }
            if let v = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }

    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return underlying.code == Int(EPERM) || underlying.code == Int(EACCES)
        }
        return false
    }

    // MARK: actions

    func open(_ item: DownloadItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: DownloadItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openFolder() {
        NSWorkspace.shared.open(settings.folderURL)
    }

    func quickLook(_ item: DownloadItem) {
        TrayQuickLookSource.shared.show([item.url]) // Support/Ext-C2.swift (tray's Quick Look source)
    }

    /// Copies the item into the Tray (Tray.addFilesFromURLs copies when "Copy files" is on).
    func addToTray(_ item: DownloadItem) {
        Tray.shared.addFilesFromURLs([item.url])
    }

    func copyToPasteboard(_ item: DownloadItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.url as NSURL])
    }

    // MARK: Clear Old

    /// Finds the items older than `clearAfterDays` (asynchronously; `clearPlan` is set when done,
    /// unless the request was withdrawn meanwhile: cancelled, folder changed, watcher torn down).
    func prepareClear() {
        guard let folder, !isPreparingClear, !isClearing else { return }
        isPreparingClear = true
        clearMessage = nil
        let s = settings
        let token = clearToken
        Self.scanQueue.async {
            let plan = Self.oldItems(in: folder, days: s.clearAfterDays, now: Date())
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let w = DownloadsWatcher.shared
                    guard token == w.clearToken, w.folder == folder else { return }
                    w.isPreparingClear = false
                    w.clearPlan = plan
                }
            }
        }
    }

    func cancelClear() {
        withdrawClearPlan()
    }

    /// Drops the pending plan and any plan still being prepared.
    private func withdrawClearPlan() {
        clearToken &+= 1
        if isPreparingClear { isPreparingClear = false }
        if clearPlan != nil { clearPlan = nil }
    }

    func dismissClearMessage() {
        clearMessage = nil
    }

    /// Moves the confirmed plan's items to the Trash — only those that are still old, complete and
    /// the same items (re-checked on the scan queue: a file deleted since and replaced by a new
    /// download with the same name, or one that became a partial download, is left alone).
    func confirmClear() {
        guard let plan = clearPlan, let folder, !isClearing else { return }
        clearPlan = nil
        isClearing = true
        let token = clearToken
        Self.scanQueue.async {
            let fresh = Self.oldItems(in: folder, days: plan.days, now: Date(), measure: false)
            let confirmed = Self.revalidated(plan, against: fresh)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let w = DownloadsWatcher.shared
                    w.isClearing = false
                    guard token == w.clearToken, w.folder == folder else { return }
                    w.recycle(confirmed, automatic: false)
                }
            }
        }
    }

    /// The plan's items that a fresh look at the folder still picks (same path, still old).
    nonisolated static func revalidated(_ plan: ClearPlan, against fresh: ClearPlan) -> ClearPlan {
        let still = Set(fresh.urls.map(\.standardizedFileURL))
        var result = plan
        result.urls = plan.urls.filter { still.contains($0.standardizedFileURL) }
        return result
    }

    private func recycle(_ plan: ClearPlan, automatic: Bool) {
        guard !plan.urls.isEmpty else {
            if !automatic { clearMessage = String(localized: "Nothing to clear.") }
            return
        }
        isClearing = true
        NSWorkspace.shared.recycle(plan.urls) { trashed, error in
            let count = trashed.count
            let failure = error?.localizedDescription
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let w = DownloadsWatcher.shared
                    w.isClearing = false
                    if let failure {
                        w.clearMessage = failure
                    } else if !automatic {
                        w.clearMessage = String(format: String(localized: "Moved %lld items to the Trash."), count)
                    }
                    NSLog("[Downloads] %@ moved %ld of %ld items to the Trash%@", automatic ? "auto-clear" : "Clear Old",
                          count, plan.urls.count, failure.map { ": \($0)" } ?? "")
                    w.scheduleScan(after: 0.2)
                }
            }
        }
    }

    private func autoClearIfDue() {
        guard let folder, !isClearing, !isPreparingClear else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastAutoClearKey) as? Date
        if let last, Date().timeIntervalSince(last) < Self.autoClearInterval { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastAutoClearKey)
        let days = settings.clearAfterDays
        Self.scanQueue.async {
            let plan = Self.oldItems(in: folder, days: days, now: Date())
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let w = DownloadsWatcher.shared
                    // still on, same folder
                    guard w.settings.autoClear, w.folder == folder, !plan.urls.isEmpty else { return }
                    w.recycle(plan, automatic: true)
                }
            }
        }
    }

    /// Top-level items added more than `days` ago: never hidden files, never downloads in progress.
    nonisolated static func oldItems(in folder: URL, days: Int, now: Date, measure: Bool = true) -> ClearPlan {
        let cutoff = now.addingTimeInterval(-TimeInterval(max(days, 1)) * 86_400)
        let urls = (try? FileManager().contentsOfDirectory(at: folder, includingPropertiesForKeys: resourceKeys,
                                                            options: [.skipsHiddenFiles])) ?? []
        var picked: [URL] = []
        var bytes: Int64 = 0
        for url in urls {
            guard let e = entry(for: url), e.partial == nil, e.added < cutoff else { continue }
            if (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true { continue }
            picked.append(url)
            guard measure else { continue }
            bytes += e.isDirectory ? (directorySize(url) ?? 0) : (e.size ?? 0)
        }
        return ClearPlan(urls: picked, bytes: bytes, days: days)
    }

    // MARK: debug

    #if DEBUG
    var debugDescription: String {
        "folder=\(folder?.path ?? "nil") status=\(status) running=\(isRunning) source=\(source != nil) poll=\(pollTimer != nil) visible=\(presence.visibleCount) inNook=\(presence.isInNook) items=\(items.count)/\(totalCount) published=\(published.keys.sorted()) progress=\(progress.map { "\(($0.key as NSString).lastPathComponent):\($0.value.fraction.map { String(format: "%.2f", $0) } ?? "?")/\($0.value.bytes)\($0.value.isStalled ? "/stalled" : "")" }.sorted()) active=\(hasActiveDownloads)/\(activeCount)"
    }
    #endif
}
