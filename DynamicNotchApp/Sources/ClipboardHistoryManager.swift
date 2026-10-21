// Clipboard history (UI requirement (4), user request 2026-10-20).
//
// Watches NSPasteboard.general by polling `changeCount` every 0.5 s on the main run loop (reading
// `changeCount` is a cheap Mach call; the pasteboard is only read when it changed). Records text,
// and — when enabled — small images (PNG, ≤ `maxImageBytes`) and copied files (file references),
// with the time and the frontmost app as the probable source. Consecutive duplicates are merged
// (the existing entry moves its timestamp forward). Contents marked by password managers as
// concealed / transient / auto-generated (nspasteboard.org conventions) and copies made while an
// excluded app is frontmost are never recorded.
//
// Polling runs only while the Clipboard widget is in the Nook and recording is on
// (ClipboardWidgetSettings.isRecording). It deliberately does not pause while the app is hidden:
// DynamicNotch is an agent app that is practically never hidden, and pausing would silently lose
// copies made in other apps — the whole point of the feature.
//
// Persistence (personal use, local only): `~/Library/Application Support/<bundle id>/ClipboardHistory.json`
// (file mode 0600) and the images in `…/<bundle id>/ClipboardImages/<uuid>.png`. Nothing leaves the Mac.
//
// The item model and the list rules (capture choice, consecutive-duplicate merge, limit, re-copy,
// which image files become unreferenced) are pure: ClipboardHistory.swift (documented and tested
// there). This class does the AppKit side: pasteboard polling and writing, files, thumbnails.
import AppKit
import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class ClipboardHistoryManager {
    static let shared = ClipboardHistoryManager()

    /// Newest first.
    var items: [ClipboardItem] { history.items }
    private var history = ClipboardHistory()
    /// Whether the pasteboard is being watched right now.
    private(set) var isPolling = false

    static let pollInterval: TimeInterval = 0.5
    static let maxTextLength = ClipboardCapture.maxTextLength
    static let maxImageBytes = ClipboardCapture.maxImageBytes

    @ObservationIgnored private let pasteboard = NSPasteboard.general
    @ObservationIgnored private var lastChangeCount = -1
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private let ioQueue = DispatchQueue(label: "dynamicnotch.clipboard-history.io", qos: .utility)
    @ObservationIgnored private let thumbnails = NSCache<NSString, NSImage>()

    private init() {}

    // MARK: - Lifecycle

    /// Loads the history and starts following the settings (idempotent). Polling itself runs only
    /// while the Clipboard widget is in the Nook and recording is on.
    func start() {
        guard !started else { return }
        started = true
        load()
        reconcile()
        settingsTask = Task { @MainActor [weak self] in
            for await _ in SettingsStore.updates([.nookSettings, .clipboardWidgetSettings], initial: false) {
                self?.reconcile()
            }
        }
    }

    private var settings: ClipboardWidgetSettings { SettingsStore[.clipboardWidgetSettings] }

    private func reconcile() {
        let shouldPoll = settings.isRecording && SettingsStore[.nookSettings].widgets.contains(.clipboard)
        if shouldPoll != isPolling {
            shouldPoll ? startPolling() : stopPolling()
        }
        trimToLimit()
    }

    private func startPolling() {
        isPolling = true
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    private func stopPolling() {
        isPolling = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Capture

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if let item = readCurrentItem() {
            record(item)
        }
    }

    private func readCurrentItem() -> ClipboardItem? {
        let types = pasteboard.types ?? []
        let source = NSWorkspace.shared.frontmostApplication
        let sourceID = source?.bundleIdentifier
        let settings = self.settings
        guard ClipboardCapture.mayRecord(types: types.map(\.rawValue), sourceBundleID: sourceID,
                                         excludedBundleIDs: settings.excludedBundleIDs) else { return nil }

        let hasFileURLType = types.contains(.fileURL)
        let urls = settings.captureFiles && hasFileURLType
            ? (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            : []
        let string = hasFileURLType ? nil : pasteboard.string(forType: .string)
        var png: Data?
        let choice = ClipboardCapture.choose(
            hasFileURLType: hasFileURLType, hasFileURLs: !urls.isEmpty, string: string,
            hasImage: { png = currentPNGData(); return png != nil },
            captureFiles: settings.captureFiles, captureImages: settings.captureImages)

        var item: ClipboardItem?
        switch choice {
        case .files:
            item = ClipboardItem(kind: .files, filePaths: urls.map(\.path))
        case .text:
            item = string.flatMap { ClipboardCapture.textItem($0) }
        case .image:
            guard let png else { return nil }
            let rep = NSBitmapImageRep(data: png)
            let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
            if let top = history.topImage(withHash: hash) {
                item = ClipboardItem(kind: .image, imageFileName: top.imageFileName,
                                     imageWidth: top.imageWidth, imageHeight: top.imageHeight, imageHash: hash)
            } else {
                let name = UUID().uuidString + ".png"
                writeImage(png, name: name)
                item = ClipboardItem(kind: .image, imageFileName: name,
                                     imageWidth: rep.map { Double($0.pixelsWide) },
                                     imageHeight: rep.map { Double($0.pixelsHigh) }, imageHash: hash)
            }
        case .nothing:
            return nil
        }
        item?.sourceBundleID = sourceID
        item?.sourceAppName = source?.localizedName
        return item
    }

    /// PNG data of the image on the pasteboard (PNG as is, TIFF converted), nil when too large.
    private func currentPNGData() -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png.count <= Self.maxImageBytes ? png : nil
        }
        guard let tiff = pasteboard.data(forType: .tiff), tiff.count <= Self.maxImageBytes * 4,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.count <= Self.maxImageBytes ? png : nil
    }

    private func record(_ item: ClipboardItem) {
        removeImageFiles(history.record(item, limit: settings.historyLimit))
        scheduleSave()
    }

    private func trimToLimit() {
        guard history.items.count > ClipboardHistory.normalizedLimit(settings.historyLimit) else { return }
        removeImageFiles(history.trim(to: settings.historyLimit))
        scheduleSave()
    }

    // MARK: - Actions

    /// Puts the item back on the clipboard and moves it to the top of the history.
    @discardableResult
    func copy(_ item: ClipboardItem) -> Bool {
        pasteboard.clearContents()
        let ok: Bool
        switch item.kind {
        case .text:
            ok = pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            if let url = imageURL(for: item), let image = NSImage(contentsOf: url) {
                ok = pasteboard.writeObjects([image])
            } else {
                ok = false
            }
        case .files:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            ok = !urls.isEmpty && pasteboard.writeObjects(urls)
        }
        // our own write is not a new copy
        lastChangeCount = pasteboard.changeCount
        guard ok else { return false }
        if history.promote(id: item.id, date: Date()) { scheduleSave() }
        return true
    }

    func delete(_ item: ClipboardItem) {
        removeImageFiles(history.remove(id: item.id))
        scheduleSave()
    }

    func clear() {
        removeImageFiles(history.removeAll())
        scheduleSave()
    }

    // MARK: - Images

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return Self.imagesDirectory.appendingPathComponent(name)
    }

    /// Image of an `.image` item (cached).
    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        if let cached = thumbnails.object(forKey: name as NSString) { return cached }
        guard let url = imageURL(for: item), let image = NSImage(contentsOf: url) else { return nil }
        thumbnails.setObject(image, forKey: name as NSString)
        return image
    }

    private func writeImage(_ data: Data, name: String) {
        let url = Self.imagesDirectory.appendingPathComponent(name)
        ioQueue.async {
            try? FileManager.default.createDirectory(at: Self.imagesDirectory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Deletes image files the history no longer references (ClipboardHistory returns them).
    private func removeImageFiles(_ names: [String]) {
        for name in names {
            thumbnails.removeObject(forKey: name as NSString)
            let url = Self.imagesDirectory.appendingPathComponent(name)
            ioQueue.async { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: - Persistence

    nonisolated static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "DynamicNotch", isDirectory: true)
    }()
    nonisolated static let historyURL = directory.appendingPathComponent("ClipboardHistory.json")
    nonisolated static let imagesDirectory = directory.appendingPathComponent("ClipboardImages", isDirectory: true)

    private func load() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        let fm = FileManager.default
        var loaded = ClipboardHistory(items: decoded)
        loaded.dropMissingImages { fm.fileExists(atPath: Self.imagesDirectory.appendingPathComponent($0).path) }
        history = loaded
        removeOrphanedImages()
    }

    private func removeOrphanedImages() {
        let referenced = history.referencedImageFiles
        ioQueue.async {
            let fm = FileManager.default
            let names = (try? fm.contentsOfDirectory(atPath: Self.imagesDirectory.path)) ?? []
            for name in names where !referenced.contains(name) {
                try? fm.removeItem(at: Self.imagesDirectory.appendingPathComponent(name))
            }
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveNow() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        ioQueue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? data.write(to: Self.historyURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.historyURL.path)
        }
    }
}
