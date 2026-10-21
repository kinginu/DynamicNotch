// Tray — the notch's file shelf: files dropped on (or pasted into) the tray, their selection,
// renaming, stacks, persistence and the `.tray` live activity.
//
// Storage: dropped files are copied (Settings ▸ Tray ▸ Copy files, the default) into
// `~/Library/Caches/<bundle id>/TrayFiles/<UUID>/<original name>`, or referenced in place. The
// contents are saved to `TrayFiles/trayState.json` when "Keep files after quit" is on; otherwise
// the previous session's copies are deleted at launch. A folder monitor prunes items whose file
// disappeared (deleted in Finder, emptied caches, …).
//
// Selection follows Finder: click selects one file, ⇧-click extends a range from the anchor,
// ⌘-click toggles. While the tray is on screen a key monitor handles ⌘A ⌘C ⌘V, Space (Quick
// Look), ⌫ (remove), Return (rename) and the arrow keys.
import AppKit
import Observation
import Quartz
import SwiftUI
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "tray")

@MainActor
@Observable
final class Tray {
    static let shared = Tray()

    /// Key codes the tray handles (macOS virtual key codes, kVK_*).
    enum KeyCode: UInt16 {
        case a = 0          // kVK_ANSI_A — select all (⌘A)
        case c = 8          // kVK_ANSI_C — copy (⌘C)
        case v = 9          // kVK_ANSI_V — paste (⌘V)
        case space = 49     // kVK_Space — toggle Quick Look
        case enter = 36     // kVK_Return — rename / commit the rename
        case escape = 53    // kVK_Escape — cancel the rename
        case delete = 51    // kVK_Delete — remove selected
        case upArrow = 126  // kVK_UpArrow (also ←, see normalizedKeyCode)
        case downArrow = 125 // kVK_DownArrow (also →)
    }

    /// A tray entry: a single file, or a stack of files dropped together.
    enum TrayItem: Identifiable {
        case file(TrayFile)
        case stack(id: UUID, files: [TrayFile], name: String)

        var id: AnyHashable {
            switch self {
            case .file(let file): return AnyHashable(file.id)
            case .stack(let id, _, _): return AnyHashable(id)
            }
        }
    }

    // MARK: - State

    /// Tray contents in display order. Setting it persists the tray and syncs the live activity.
    var files: [TrayFile] {
        get { storedFiles }
        set {
            storedFiles = newValue
            filesDidChange()
        }
    }
    private var storedFiles: [TrayFile] = []

    var selectedFiles: [TrayFile] = []

    /// The file being renamed and its edited name.
    var editingFile: (file: TrayFile, newName: String)? = nil

    /// Range-selection anchor and moving end (indices into `files`; may be stale, see `validIndex`).
    @ObservationIgnored private var baseFileIndex: Int? = nil
    @ObservationIgnored private var lastSelectedIndex: Int? = nil

    @ObservationIgnored private var tempDirectory: URL? = nil
    @ObservationIgnored private var stateFileURL: URL? = nil
    @ObservationIgnored private var folderMonitor: FolderMonitor? = nil
    @ObservationIgnored private var keyDownMonitor: Any? = nil

    // App-lifetime singleton: the folder monitor is never torn down.
    private init() {
        setupTempDirectory()
        if SettingsStore[.traySettings].keepFilesAfterQuit {
            storedFiles = loadPersistedFiles() // no persist / live-activity side effects in init
        } else {
            removeAllStoredCopies()
        }
        setupFolderMonitor()
        // Deferred: inserting the `.tray` live activity re-renders views that read Tray.shared
        // (TrayFilesCountView); doing it inside the initializer re-entered the `static let shared`
        // initialization (dispatch_once trap).
        DispatchQueue.main.async {
            MainActor.assumeIsolated { Tray.shared.updateLiveActivity() }
        }
    }

    // MARK: - Items and stacks

    /// Files grouped into items in tray order (a stack sits where its first file was added, so
    /// items don't jump around between renders); a "stack" of one file is shown as a file.
    var trayItems: [TrayItem] {
        let allFiles = storedFiles
        var grouped: [UUID: [TrayFile]] = [:]
        for file in allFiles {
            if let stackID = file.stackID {
                grouped[stackID, default: []].append(file)
            }
        }
        var result: [TrayItem] = []
        var emitted = Set<UUID>()
        for file in allFiles {
            if let stackID = file.stackID, let stackFiles = grouped[stackID] {
                if stackFiles.count < 2 {
                    result.append(.file(file))
                } else if !emitted.contains(stackID) {
                    emitted.insert(stackID)
                    result.append(.stack(id: stackID, files: stackFiles, name: stackName(for: stackFiles)))
                }
            } else {
                result.append(.file(file))
            }
        }
        return result
    }

    /// "PNGs 3" when all files share an extension, else "5 files".
    func stackName(for files: [TrayFile]) -> String {
        guard !files.isEmpty else { return "0 files" }
        var extensionCounts: [String: Int] = [:]
        for file in files {
            extensionCounts[file.url.pathExtension.lowercased(), default: 0] += 1
        }
        if extensionCounts.count == 1, let ext = extensionCounts.keys.first {
            return "\(ext.uppercased())s \(files.count)"
        }
        return "\(files.count) files"
    }

    /// Splits a stack back into single files.
    func unstack(_ stackID: UUID) {
        for file in storedFiles where file.stackID == stackID { file.stackID = nil }
        files = storedFiles // notify + persist
        resetSelectionAnchor()
    }

    // MARK: - Adding files

    func addFile(_ file: TrayFile) {
        withAnimation(.spring(response: 1.0, dampingFraction: 0.5, blendDuration: 0)) {
            guard !storedFiles.contains(where: { $0 == file }) else { return }
            storedFiles.append(file)
        }
        filesDidChange()
    }

    /// Copies (TraySettings.copyFiles) or references dropped files; two or more files dropped
    /// together form a stack. Copies go to `<tray>/<UUID>/<original name>` off the main thread
    /// (large files would otherwise freeze the notch); `completion` gets the added files.
    func addFilesFromURLs(_ urls: [URL], completion: (([TrayFile]) -> Void)? = nil) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty, let tempDir = tempDirectory else { completion?([]); return }
        let stackID: UUID? = fileURLs.count >= 2 ? UUID() : nil

        guard SettingsStore[.traySettings].copyFiles else {
            let added = fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
                .map { TrayFile(url: $0, stackID: stackID) }
            added.forEach(addFile)
            completion?(added)
            return
        }

        Task {
            let copied = await Self.copyIntoTray(fileURLs, directory: tempDir)
            let added = copied.map { TrayFile(url: $0, stackID: stackID) }
            added.forEach(addFile)
            completion?(added)
        }
    }

    /// Copies each file into its own `<directory>/<UUID>/` folder on a background queue.
    nonisolated private static func copyIntoTray(_ urls: [URL], directory: URL) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                var copied: [URL] = []
                for sourceURL in urls where fileManager.fileExists(atPath: sourceURL.path) {
                    let itemDir = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    let destURL = itemDir.appendingPathComponent(sourceURL.lastPathComponent)
                    do {
                        try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
                        try fileManager.copyItem(at: sourceURL, to: destURL)
                        copied.append(destURL)
                    } catch {
                        logger.error("could not copy \(sourceURL.lastPathComponent, privacy: .public) into the tray: \(String(describing: error), privacy: .public)")
                        try? fileManager.removeItem(at: itemDir)
                    }
                }
                continuation.resume(returning: copied)
            }
        }
    }

    /// Adds files that already live in the tray folder (generated text / images, received file
    /// promises) without copying them again.
    @discardableResult
    func adoptFiles(_ urls: [URL]) -> [TrayFile] {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        let stackID: UUID? = existing.count >= 2 ? UUID() : nil
        let added = existing.map { TrayFile(url: $0, stackID: stackID) }
        added.forEach(addFile)
        return added
    }

    /// A new, empty `<tray>/<UUID>/` folder for one generated / promised item.
    func newItemDirectory() -> URL {
        let base = tempDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("TrayFiles")
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("could not create a tray item folder: \(String(describing: error), privacy: .public)")
        }
        return dir
    }

    /// Pastes file URLs (copied / referenced like a drop), else PNG / TIFF / text (written into a
    /// new tray item folder).
    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            addFilesFromURLs(urls)
            return
        }
        if let generated = TrayDropContent.materialize(pasteboard: pasteboard, into: newItemDirectory()) {
            adoptFiles(generated)
        }
    }

    // MARK: - Removing files

    /// Removes the selection (`currentFile` nil), or `currentFile` if it is selected.
    func removeSelectedFiles(currentFile: TrayFile?) {
        guard currentFile == nil else {
            if let target = selectedFiles.first(where: { $0 == currentFile }) {
                removeFile(target)
            }
            return
        }
        let selectedURLs = Set(selectedFiles.map(\.url))
        let removed = storedFiles.filter { selectedURLs.contains($0.url) }
        files = storedFiles.filter { !selectedURLs.contains($0.url) }
        selectedFiles = []
        resetSelectionAnchor()
        removed.forEach(deleteStoredCopy)
    }

    /// Removes one file (by instance: `==` compares inodes, which by-reference items can share),
    /// drops it from the selection and deletes the tray's own copy.
    func removeFile(_ file: TrayFile) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0)) {
            files = storedFiles.filter { $0 !== file }
            if selectedFiles.contains(where: { $0 === file }) {
                selectedFiles = selectedFiles.filter { $0 !== file }
            }
        }
        resetSelectionAnchor()
        deleteStoredCopy(file)
    }

    func remove(_ files: [TrayFile]) {
        files.forEach(removeFile)
    }

    /// Removes every item (Clear button / settings).
    func removeAll() {
        let all = storedFiles
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0)) {
            files = []
            selectedFiles = []
        }
        resetSelectionAnchor()
        editingFile = nil
        all.forEach(deleteStoredCopy)
    }

    /// true when `url` is inside the tray's own folder (a copy the tray owns).
    func isStoredCopy(_ url: URL) -> Bool {
        guard let dir = tempDirectory else { return false }
        return url.standardizedFileURL.path.hasPrefix(dir.standardizedFileURL.path + "/")
    }

    /// Deletes the tray's copy of `file` (its `<tray>/<UUID>/` folder). Referenced originals are
    /// never touched.
    func deleteStoredCopy(_ file: TrayFile) {
        let url = file.url
        guard isStoredCopy(url), let dir = tempDirectory else { return }
        let parent = url.deletingLastPathComponent()
        let target = parent.standardizedFileURL.path == dir.standardizedFileURL.path ? url : parent
        // keep it if another tray entry still points into the same folder
        if target == parent && storedFiles.contains(where: { $0.url.deletingLastPathComponent() == parent }) { return }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            logger.error("could not delete the tray copy \(target.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes the stored copies and the state file without touching `files` (at launch when
    /// "Keep files after quit" is off).
    func removeAllStoredCopies() {
        guard let dir = tempDirectory,
              let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }

    // MARK: - Selection

    func selectFile(_ file: TrayFile?) {
        guard let file else {
            selectedFiles = []
            resetSelectionAnchor()
            editingFile = nil
            return
        }
        let clickIdx = storedFiles.firstIndex(where: { $0 === file }) ?? storedFiles.firstIndex(where: { $0 == file })

        if isCommandPressed() {
            if let existingIdx = selectedFiles.firstIndex(where: { $0 == file }) {
                selectedFiles.remove(at: existingIdx)
            } else {
                selectedFiles.append(file)
            }
            setSelectionAnchor(clickIdx)
        } else if isShiftPressed(), let clickIdx, let baseIdx = validIndex(baseFileIndex) {
            selectedFiles = Array(storedFiles[min(baseIdx, clickIdx)...max(baseIdx, clickIdx)])
            // the anchor stays where the range started; only the moving end changes
            lastSelectedIndex = clickIdx
        } else {
            selectedFiles = [file]
            setSelectionAnchor(clickIdx)
        }
        editingFile = nil
    }

    func selectAllFiles() {
        selectedFiles = storedFiles
        baseFileIndex = 0
        if !storedFiles.isEmpty {
            lastSelectedIndex = storedFiles.count - 1
        }
    }

    /// Files an action applies to: the selection when `file` is part of it, else just `file`.
    func actionTargets(for file: TrayFile) -> [TrayFile] {
        selectedFiles.contains(where: { $0 === file }) ? selectedFiles : [file]
    }

    /// Clears the range anchor; called whenever `files` changes shape (remove, prune, unstack).
    func resetSelectionAnchor() {
        baseFileIndex = nil
        lastSelectedIndex = nil
    }

    /// `index` if it still addresses an element of `files`.
    private func validIndex(_ index: Int?) -> Int? {
        guard let index, storedFiles.indices.contains(index) else { return nil }
        return index
    }

    private func setSelectionAnchor(_ index: Int?) {
        baseFileIndex = index
        lastSelectedIndex = index
    }

    /// ⇧↑ / ⇧↓: extends the range from the anchor.
    private func handleShiftArrowSelection(direction: Int) {
        guard !storedFiles.isEmpty else { return }
        let maxIndex = storedFiles.count - 1
        // stored indices can be stale after a removal: re-derive them from the selection
        var lastIdx = validIndex(lastSelectedIndex)
        if selectedFiles.isEmpty || lastIdx == nil {
            if let last = selectedFiles.last, let idx = storedFiles.firstIndex(where: { $0 === last }) {
                lastIdx = idx
            } else {
                lastIdx = 0
                selectedFiles = [storedFiles[0]]
            }
            setSelectionAnchor(lastIdx)
        }
        guard let lastIdx else { return }
        let newIdx = max(0, min(lastIdx + direction, maxIndex))
        lastSelectedIndex = newIdx
        let baseIdx = validIndex(baseFileIndex) ?? lastIdx
        baseFileIndex = baseIdx
        selectedFiles = Array(storedFiles[min(baseIdx, newIdx)...max(baseIdx, newIdx)])
    }

    /// ↑ / ↓: selects the previous / next file.
    private func selectAdjacentFile(direction: Int) {
        guard !storedFiles.isEmpty else { return }
        let currentIndex = selectedFiles.last.flatMap { last in storedFiles.firstIndex(where: { $0 == last }) }
        let newIdx = max(0, min((currentIndex ?? 0) + direction, storedFiles.count - 1))
        selectFile(storedFiles[newIdx])
    }

    private func isCommandPressed() -> Bool { NSEvent.modifierFlags.contains(.command) }
    private func isShiftPressed() -> Bool { NSEvent.modifierFlags.contains(.shift) }

    // MARK: - File actions

    func open(_ files: [TrayFile]) {
        files.forEach { NSWorkspace.shared.open($0.url) }
    }

    func revealInFinder(_ files: [TrayFile]) {
        NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url))
    }

    func copyToClipboard(_ files: [TrayFile]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(files.map { $0.url as NSURL })
    }

    func airDrop(_ files: [TrayFile]) {
        airDropItems(items: files.map(\.url))
    }

    func beginRenaming(_ file: TrayFile) {
        guard canRename(file) else { return }
        selectedFiles = [file]
        editingFile = (file: file, newName: file.name)
    }

    /// Only the tray's own copies can be renamed: a by-reference item (Copy files off) is the
    /// user's original file, which the tray must not rename behind their back.
    func canRename(_ file: TrayFile) -> Bool {
        guard let tempDirectory else { return false }
        let base = tempDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let path = file.url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// Commits the rename in progress (and saves the new location: "Keep files after quit").
    func rename() {
        guard let editing = editingFile else { return }
        editingFile = nil
        guard canRename(editing.file) else { return }
        do {
            try editing.file.rename(to: editing.newName)
            filesDidChange()
        } catch {
            // logged by TrayFile; the item keeps its old name
        }
    }

    private func toggleQuickLookState() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // the selected files, or all files when nothing is selected
            let urls = (selectedFiles.isEmpty ? storedFiles : selectedFiles).map(\.url)
            guard !urls.isEmpty else { return }
            TrayQuickLookSource.shared.show(urls)
        }
    }

    // MARK: - Keyboard

    /// Installs the key monitor while the tray is on screen.
    func startKeyboardMonitoring() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    func stopKeyboardMonitoring() {
        guard let monitor = keyDownMonitor else { return }
        NSEvent.removeMonitor(monitor)
        keyDownMonitor = nil
    }

    /// ←/→ move like ↑/↓ (the tray is a horizontal strip), forward delete and keypad Enter like
    /// their main-keyboard counterparts.
    static func normalizedKeyCode(_ keyCode: UInt16) -> UInt16 {
        switch keyCode {
        case 123: return KeyCode.upArrow.rawValue    // kVK_LeftArrow
        case 124: return KeyCode.downArrow.rawValue  // kVK_RightArrow
        case 117: return KeyCode.delete.rawValue     // kVK_ForwardDelete
        case 76: return KeyCode.enter.rawValue       // kVK_ANSI_KeypadEnter
        default: return keyCode
        }
    }

    /// Returns nil when the tray consumed the event.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // only while the tray is on screen, without ⌃ / ⌥, and not while a text field edits
        guard DynamicNotchState.shared.mode == .tray,
              event.modifierFlags.intersection([.control, .option]).isEmpty else { return event }
        if NSApplication.shared.keyWindow?.firstResponder is NSText { return event }
        guard let key = KeyCode(rawValue: Self.normalizedKeyCode(event.keyCode)) else { return event }
        return editingFile != nil ? handleEditingKey(event, key) : handleNonEditingKey(event, key)
    }

    private func handleEditingKey(_ event: NSEvent, _ key: KeyCode) -> NSEvent? {
        guard selectedFiles.count == 1 else { return event }
        switch key {
        case .escape:
            editingFile = nil
            return nil
        case .enter:
            rename()
            return nil
        default:
            return event
        }
    }

    private func handleNonEditingKey(_ event: NSEvent, _ key: KeyCode) -> NSEvent? {
        switch key {
        case .a where isCommandPressed():
            selectAllFiles()
            return nil
        case .c where isCommandPressed():
            copyToClipboard(selectedFiles)
            return nil
        case .v where isCommandPressed():
            pasteFromClipboard()
            return nil
        case .space:
            toggleQuickLookState()
            return nil
        case .enter where selectedFiles.count == 1:
            let file = selectedFiles[0]
            guard canRename(file) else { return event }
            editingFile = (file: file, newName: file.name)
            return nil
        case .delete:
            withAnimation(.spring(response: 1.0, dampingFraction: 0.5, blendDuration: 0)) {
                removeSelectedFiles(currentFile: nil)
            }
            return nil
        case .upArrow, .downArrow:
            let direction = key == .upArrow ? -1 : 1
            if isShiftPressed() {
                handleShiftArrowSelection(direction: direction)
            } else {
                selectAdjacentFile(direction: direction)
            }
            return nil
        default:
            return event
        }
    }

    // MARK: - Persistence and live activity

    /// Called after every change of `files`: persist ("Keep files after quit") and keep the
    /// `.tray` live activity in sync.
    func filesDidChange() {
        if SettingsStore[.traySettings].keepFilesAfterQuit {
            persist()
        } else if let stateFileURL, FileManager.default.fileExists(atPath: stateFileURL.path) {
            try? FileManager.default.removeItem(at: stateFileURL)
        }
        updateLiveActivity()
    }

    /// Requests / removes the `.tray` live activity (writes only on change).
    func updateLiveActivity() {
        let manager = ActiveLiveActivitiesManager.shared
        let shouldShow = !storedFiles.isEmpty && SettingsStore[.traySettings].showLiveActivity
        // the request, not the visible set (which the Live Activities settings filter): a request
        // hidden by a disabled toggle must still be withdrawn when the tray empties
        let isShown = manager.requestedActivities.contains(.tray)
        if shouldShow && !isShown {
            manager.insertSync(.tray)
        } else if !shouldShow && isShown {
            manager.removeSync(.tray)
        }
    }

    /// Folder that holds the tray's copies (Settings ▸ Tray ▸ Show in Finder).
    var storageDirectory: URL? { tempDirectory }

    /// Persisted form of a tray file (`trayState.json`).
    private struct TrayFileRecord: Codable {
        let url: URL
        let addedAt: Date
        let name: String
        let stackID: UUID?
    }

    private func persist() {
        guard let stateFileURL else { return }
        let records = storedFiles.map { TrayFileRecord(url: $0.url, addedAt: $0.addedAt, name: $0.name, stackID: $0.stackID) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(records).write(to: stateFileURL, options: .atomic)
        } catch {
            logger.error("tray state not saved: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadPersistedFiles() -> [TrayFile] {
        guard let stateFileURL, FileManager.default.fileExists(atPath: stateFileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records: [TrayFileRecord]
        do {
            records = try decoder.decode([TrayFileRecord].self, from: Data(contentsOf: stateFileURL))
        } catch {
            logger.error("tray state unreadable, starting empty: \(String(describing: error), privacy: .public)")
            return []
        }
        return records.compactMap { record in
            guard FileManager.default.fileExists(atPath: record.url.path) else {
                logger.notice("tray file no longer exists: \(record.url.lastPathComponent, privacy: .public)")
                return nil
            }
            let file = TrayFile(url: record.url, stackID: record.stackID)
            file.addedAt = record.addedAt
            return file
        }
    }

    private func setupTempDirectory() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let trayURL = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "DynamicNotch", isDirectory: true)
            .appendingPathComponent("TrayFiles", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: trayURL, withIntermediateDirectories: true)
            tempDirectory = trayURL
            stateFileURL = trayURL.appendingPathComponent("trayState.json")
        } catch {
            logger.error("could not create the TrayFiles folder: \(String(describing: error), privacy: .public)")
        }
    }

    private func setupFolderMonitor() {
        guard let dir = tempDirectory else { return }
        folderMonitor = FolderMonitor(path: dir.path) { [weak self] in
            self?.pruneMissingFiles()
        }
    }

    /// Drops items whose file disappeared. (`files` is not rebuilt from the folder listing: with one
    /// sub-folder per item, the state file in the same folder and by-reference items elsewhere,
    /// that would list folders / state files and drop referenced items.)
    private func pruneMissingFiles() {
        let remaining = storedFiles.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard remaining.count != storedFiles.count else { return }
        let paths = Set(remaining.map(\.url.path))
        files = remaining
        selectedFiles = selectedFiles.filter { paths.contains($0.url.path) }
        resetSelectionAnchor() // indices are stale after a prune
    }
}
