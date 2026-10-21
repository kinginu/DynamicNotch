// Dropping files onto the notch: NotchDropModifier / NotchDropController (drag lifecycle and drop
// routing), TrayDropContent (pasteboard content → files) and NotchDropTempFiles (AirDrop shares
// of generated files and their cleanup).
//
// NotchView applies `NotchDropModifier` to the footprint-sized gesture layer behind the content
// (closed and open). The modifier puts an AppKit drop destination (FileDropView.DropAreaView)
// behind that layer and owns the whole drag lifecycle through `NotchDropController`:
//
//   - drag enters the notch (or, while the notch is closed and fully transparent, comes near it —
//     detected with a global mouse-dragged monitor + the drag pasteboard's change count, which
//     needs no permission) → `DynamicNotchState.shared.mode = .dragging` → TrayView shows the
//     drop targets (Tray, AirDrop);
//   - while dragging, `NotchViewModel.droppingCoords` follows the pointer (SwiftUI global space);
//     TrayView publishes the targets' frames into `NotchViewModel.targetsCoords`, so
//     `hoveredDropTargetID` (original logic) names the target under the pointer;
//   - drop → the items (file URLs, file promises, images, links, text) go to the hovered target
//     (default: Tray); the notch then shows the tray (or closes after AirDrop);
//   - while the tray is open (.tray) its right side is a dedicated
//     AirDrop zone with its own AppKit destination (AirDropZoneDropView, DropArea.swift): drags
//     from the tray itself (which this controller ignores) and Finder drags released directly on
//     it go to `NotchDropTempFiles.airDrop(pasteboard:)`. In .dragging the zone keeps the same
//     place and size and is routed through `hoveredDropTargetID` like before;
//   - exit / mouse-up elsewhere without a drop → back to .closed.
//
// Only the Tray and AirDrop targets exist (there are no drop pipelines).
import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "tray")

struct NotchDropModifier: ViewModifier {
    let viewModel: NotchViewModel
    func body(content: Content) -> some View {
        content
            .background(FileDropView(viewModel: viewModel))
    }
}

// MARK: - Drop targets

/// Identifiers of the drop targets shown while dragging (keys of NotchViewModel.targetsCoords).
enum NotchDropTarget: String, CaseIterable {
    case tray
    case airDrop = "airdrop"
}

// MARK: - Controller

@MainActor
final class NotchDropController {
    let viewModel: NotchViewModel
    /// This screen's notch state (per-screen states).
    private var state: DynamicNotchState { viewModel.screenNotchState ?? .shared }

    /// pointer is inside this window's drop view
    private(set) var isInside = false
    /// this controller switched the notch to .dragging (multi-screen: only the owner closes it)
    private var ownsDrag = false
    /// a drop is being processed (file promises can take a while)
    private var dropInFlight = false
    private var exitTask: Task<Void, Never>?

    // Global drag detection. nonisolated(unsafe): only touched on the main actor and in deinit
    // (which runs after the last reference is gone).
    nonisolated(unsafe) private var monitors: [Any] = []
    private var mouseDownChangeCount = NSPasteboard(name: .drag).changeCount
    /// a drag session started in another app is in progress (left button down, drag pasteboard changed)
    private(set) var externalDragActive = false

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        installMonitors()
        // load the persisted tray at launch (so its `.tray` live activity shows without first
        // opening the tray); deferred out of the SwiftUI update that creates this controller
        DispatchQueue.main.async { MainActor.assumeIsolated { _ = Tray.shared } }
        #if DEBUG
        Self.debugInstance = self
        #endif
    }

    #if DEBUG
    /// last created controller (DebugHooks-C)
    static weak var debugInstance: NotchDropController?
    func debugBeginDragging() { beginDragging() }
    #endif

    deinit {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }

    // MARK: Pasteboard

    static let readableClasses: [AnyClass] = [NSURL.self, NSFilePromiseReceiver.self, NSImage.self, NSString.self]

    static var registeredTypes: [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff,
                                                     NSPasteboard.PasteboardType("public.data")]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return types
    }

    private func accepts(_ pasteboard: NSPasteboard) -> Bool {
        guard SettingsStore[.dropAreaSettings].enabled else { return false }
        return pasteboard.canReadObject(forClasses: Self.readableClasses, options: nil)
    }

    // MARK: NSDraggingDestination entry points (called by FileDropView.DropAreaView)

    func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        // drags that start inside the app (files dragged out of the tray) are not drop candidates
        guard info.draggingSource == nil, accepts(info.draggingPasteboard) else { return [] }
        cancelExit()
        isInside = true
        beginDragging()
        updateCoords(info)
        return .copy
    }

    func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        guard info.draggingSource == nil, accepts(info.draggingPasteboard) else { return [] }
        if !isInside {
            cancelExit()
            isInside = true
            beginDragging()
        }
        updateCoords(info)
        return .copy
    }

    func draggingExited() {
        isInside = false
        scheduleExit(after: 0.35)
    }

    func performDrop(_ info: NSDraggingInfo) -> Bool {
        guard info.draggingSource == nil, accepts(info.draggingPasteboard) else { return false }
        cancelExit()
        updateCoords(info)
        let target = NotchDropTarget(rawValue: viewModel.hoveredDropTargetID ?? "") ?? .tray
        let target2 = (target == .airDrop && !SettingsStore[.dropAreaSettings].showAirDropTarget) ? .tray : target
        return handleDrop(pasteboard: info.draggingPasteboard, target: target2)
    }

    func draggingEnded() {
        isInside = false
        if !dropInFlight { scheduleExit(after: 0.2) }
    }

    // MARK: Drop handling (also used by DebugHooks-C `trayadd:` / `traydrop:`)

    @discardableResult
    func handleDrop(pasteboard: NSPasteboard, target: NotchDropTarget) -> Bool {
        dropInFlight = true
        let done: ([URL]) -> Void = { [weak self] urls in
            self?.route(urls, to: target)
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            done(urls)
            return true
        }

        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver], !receivers.isEmpty {
            Self.receivePromises(receivers, target: target, completion: done)
            return true
        }

        if let generated = TrayDropContent.materialize(pasteboard: pasteboard, into: Self.destinationDirectory(for: target)) {
            done(generated)
            return true
        }

        dropInFlight = false
        finish(close: true)
        return false
    }

    /// Where promised / generated files are written: a tray item folder for the Tray target, a
    /// temporary folder for AirDrop.
    static func destinationDirectory(for target: NotchDropTarget) -> URL {
        switch target {
        case .tray:
            return Tray.shared.newItemDirectory()
        case .airDrop:
            let dir = NotchDropTempFiles.root
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logger.error("could not create an AirDrop temp folder: \(String(describing: error), privacy: .public)")
            }
            return dir
        }
    }

    static func receivePromises(_ receivers: [NSFilePromiseReceiver], target: NotchDropTarget,
                                completion: @escaping ([URL]) -> Void) {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        let group = DispatchGroup()
        let lock = NSLock()
        var received: [URL] = []
        for receiver in receivers {
            let dir = destinationDirectory(for: target)
            // one callback per promised file of this receiver; never leave the group more often
            // than it was entered (fileNames can be empty for some sources)
            var remaining = max(receiver.fileNames.count, 1)
            for _ in 0..<remaining { group.enter() }
            receiver.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: queue) { url, error in
                lock.lock()
                if let error {
                    logger.error("promised file not received: \(String(describing: error), privacy: .public)")
                } else {
                    received.append(url)
                }
                let shouldLeave = remaining > 0
                remaining -= 1
                lock.unlock()
                if shouldLeave { group.leave() }
            }
        }
        group.notify(queue: .main) {
            completion(received)
        }
    }

    private func route(_ urls: [URL], to target: NotchDropTarget) {
        dropInFlight = false
        viewModel.droppingCoords = nil
        guard !urls.isEmpty else { finish(close: true); return }
        switch target {
        case .tray:
            let tray = Tray.shared
            let own = urls.filter { tray.isStoredCopy($0) }
            let foreign = urls.filter { !tray.isStoredCopy($0) }
            if !own.isEmpty { tray.adoptFiles(own) }
            if !foreign.isEmpty { tray.addFilesFromURLs(foreign) }
            ownsDrag = false
            if state.mode != .tray {
                withAnimation(.notchOpen) { state.mode = .tray }
            }
        case .airDrop:
            // like airDropItems(items:), but removes the files this controller generated under
            // $TMPDIR/DynamicNotchTemp once the share completes or fails
            NotchDropTempFiles.airDrop(urls)
            finish(close: true)
        }
    }

    // MARK: Mode changes

    private func beginDragging() {
        ownsDrag = true
        if state.mode != .dragging {
            withAnimation(.notchOpen) { state.mode = .dragging }
        }
    }

    private func updateCoords(_ info: NSDraggingInfo) {
        guard let content = info.draggingDestinationWindow?.contentView else { return }
        let p = info.draggingLocation // window base coordinates (bottom-left origin)
        let global = CGPoint(x: p.x, y: content.bounds.height - p.y) // SwiftUI global (top-left)
        if viewModel.droppingCoords != global { viewModel.droppingCoords = global }
    }

    private func scheduleExit(after delay: TimeInterval) {
        guard ownsDrag else { return }
        exitTask?.cancel()
        exitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.isInside, !self.dropInFlight else { return }
            self.finish(close: true)
        }
    }

    private func cancelExit() {
        exitTask?.cancel()
        exitTask = nil
    }

    func finish(close: Bool) {
        cancelExit()
        if viewModel.droppingCoords != nil { viewModel.droppingCoords = nil }
        guard close, ownsDrag else { return }
        ownsDrag = false
        if state.mode == .dragging {
            withAnimation(.notchClose) { state.mode = .closed }
        }
    }

    // MARK: Global drag detection (no permission needed for mouse events)

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleGlobal(event) }
        }) {
            monitors.append(monitor)
        }
    }

    private func handleGlobal(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownChangeCount = NSPasteboard(name: .drag).changeCount
            externalDragActive = false
        case .leftMouseDragged:
            if !externalDragActive {
                let pasteboard = NSPasteboard(name: .drag)
                guard pasteboard.changeCount != mouseDownChangeCount, accepts(pasteboard) else { return }
                externalDragActive = true
            }
            let location = NSEvent.mouseLocation
            let frame = viewModel.hoverScreenFrame
            guard frame.width > 0 else { return }
            // closed: the notch is a transparent, notch-sized area at the top edge — open when the
            // pointer comes within reach; open (.dragging): close if it leaves without entering.
            let zone = frame.insetBy(dx: -28, dy: -28)
            if state.mode == .closed {
                if zone.contains(location) { beginDragging() }
            } else if state.mode == .dragging, ownsDrag, !isInside, !dropInFlight {
                if !frame.insetBy(dx: -60, dy: -60).contains(location) { scheduleExit(after: 0.2) }
            }
        case .leftMouseUp:
            externalDragActive = false
            if state.mode == .dragging, !dropInFlight { scheduleExit(after: 0.3) }
        default:
            break
        }
    }
}

// MARK: - Pasteboard → files

/// Turns non-file pasteboard content (images, links, text) into files, so the
/// tray (and AirDrop) can hold it. Writes into `directory`; returns nil (and removes the
/// directory if it is empty) when there is nothing usable.
enum TrayDropContent {
    static func materialize(pasteboard: NSPasteboard, into directory: URL) -> [URL]? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var result: [URL] = []

        if let png = pasteboard.data(forType: .png) {
            let url = directory.appendingPathComponent("Image.png")
            if (try? png.write(to: url, options: .atomic)) != nil { result.append(url) }
        } else if let tiff = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            let url = directory.appendingPathComponent("Image.png")
            if (try? png.write(to: url, options: .atomic)) != nil { result.append(url) }
        } else if let links = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  let link = links.first(where: { !$0.isFileURL }) {
            let name = sanitized(link.host ?? "Link")
            let url = directory.appendingPathComponent(name).appendingPathExtension("webloc")
            if let data = try? PropertyListSerialization.data(fromPropertyList: ["URL": link.absoluteString],
                                                              format: .xml, options: 0),
               (try? data.write(to: url, options: .atomic)) != nil {
                result.append(url)
            }
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Text"
            let name = sanitized(String(firstLine.prefix(32)))
            let url = directory.appendingPathComponent(name.isEmpty ? "Text" : name).appendingPathExtension("txt")
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil { result.append(url) }
        }

        if result.isEmpty {
            if (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty ?? false {
                try? fileManager.removeItem(at: directory)
            }
            return nil
        }
        return result
    }

    private static func sanitized(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters)
        return name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


// MARK: - AirDrop temp files

/// Promised / materialized files for the AirDrop target are written to
/// `$TMPDIR/DynamicNotchTemp/<UUID>/`. Each generated folder is removed when its share completes
/// or fails, and anything left by a previous session (crash, cancelled share sheet) is removed at
/// launch.
@MainActor
final class NotchDropTempFiles: NSObject, NSSharingServiceDelegate {
    nonisolated static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DynamicNotchTemp", isDirectory: true)
    }

    /// Shares in flight (NSSharingService keeps only a weak delegate).
    private static var active: [NotchDropTempFiles] = []

    private let service: NSSharingService
    private let generatedDirectories: [URL]

    private init(service: NSSharingService, generatedDirectories: [URL]) {
        self.service = service
        self.generatedDirectories = generatedDirectories
    }

    /// Removes everything under `root`; call once at launch, before any drop happens.
    nonisolated static func cleanUpStale() {
        cleanupTemporaryDirectory(root)
    }

    /// Sends `urls` via AirDrop and deletes the generated folders (only those under `root`, never
    /// referenced originals) when the share finishes.
    static func airDrop(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        let generated = generatedDirectories(in: fileURLs)
        guard !fileURLs.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: fileURLs) else {
            remove(generated)
            return
        }
        let share = NotchDropTempFiles(service: service, generatedDirectories: generated)
        service.delegate = share
        active.append(share)
        service.perform(withItems: fileURLs)
    }

    /// AirDrop zone of the open tray (TrayAirDropZone / AirDropZoneDropView): sends
    /// whatever was dropped there — file URLs as they are (tray copies and Finder originals are
    /// never deleted), file promises / images / links / text materialised under `root` first
    /// (removed again when the share finishes). Returns false when nothing usable was dropped.
    @discardableResult
    static func airDrop(pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            airDrop(urls)
            return true
        }
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver], !receivers.isEmpty {
            NotchDropController.receivePromises(receivers, target: .airDrop) { urls in airDrop(urls) }
            return true
        }
        if let generated = TrayDropContent.materialize(
            pasteboard: pasteboard, into: NotchDropController.destinationDirectory(for: .airDrop)) {
            airDrop(generated)
            return true
        }
        return false
    }

    /// The `<root>/<UUID>` folders that contain any of `urls`.
    private static func generatedDirectories(in urls: [URL]) -> [URL] {
        let rootPath = root.standardizedFileURL.path + "/"
        var dirs: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            let first = path.dropFirst(rootPath.count).split(separator: "/").first.map(String.init)
            guard let first, !first.isEmpty else { continue }
            let dir = root.appendingPathComponent(first, isDirectory: true)
            if !dirs.contains(dir) { dirs.append(dir) }
        }
        return dirs
    }

    nonisolated private static func remove(_ dirs: [URL]) {
        for dir in dirs { try? FileManager.default.removeItem(at: dir) }
    }

    private func complete() {
        let dirs = generatedDirectories
        Self.active.removeAll { $0 === self }
        // a short grace period: the AirDrop agent may still be reading the files when it reports
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { Self.remove(dirs) }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { complete() }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        MainActor.assumeIsolated { complete() }
    }
}
