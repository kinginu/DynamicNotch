// TrayFile — one file in the tray: its location, display names, icon and stack membership.
// Identity for `==` / hashing is the file's inode, so the same file dropped twice is recognised;
// Tray uses instance identity (`===`) where by-reference items may share an inode.
//
// The parent folder is watched with a dispatch source (on the main queue); on a change the file's
// name / inode are re-read. Renaming through `name` / `rename(to:)` moves the file and follows it.
// Created and used on the main thread only.
import AppKit
import Observation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "tray")

@Observable
final class TrayFile: Identifiable, Hashable {
    let id = UUID()

    /// Current location of the file.
    var url: URL
    /// File-system file number (identity for `==` / `hash`); nil when it could not be read.
    var inode: UInt64?
    /// `name`, shortened to "abcdef...tuvwxyz" when it has 17 characters or more.
    var nameTruncated: String
    /// Files dropped together share a stack id.
    var stackID: UUID?
    /// Finder icon (TrayFileIconView loads a Quick Look thumbnail on top of it).
    var image: Image
    var addedAt = Date()
    var isImage: Bool

    /// File name (with extension). Setting it renames the file on disk.
    var name: String {
        get { storedName }
        set {
            let oldValue = storedName
            storedName = newValue
            if oldValue != newValue {
                try? rename(to: newValue)
            }
        }
    }
    private var storedName: String

    @ObservationIgnored private var fileSystemSource: DispatchSourceFileSystemObject?

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic",
        "webp", "svg", "pdf", "eps", "ai", "psd", "raw",
        "cr2", "nef", "orf", "sr2",
    ]

    init(url: URL, stackID: UUID?) {
        self.url = url
        self.stackID = stackID
        // The Finder icon only: decoding the image itself here froze the notch on drops of large
        // photos.
        self.image = Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        let fileName = url.lastPathComponent
        self.storedName = fileName
        self.nameTruncated = Self.truncated(fileName)
        self.isImage = Self.imageExtensions.contains(url.pathExtension.lowercased())
        self.inode = Self.inode(of: url)
        startObservingFileChanges()
    }

    deinit {
        fileSystemSource?.cancel() // the cancel handler closes the descriptor
    }

    // MARK: - Renaming

    /// Renames the file on disk to `newName` and follows it. The whole typed name is kept
    /// ("report.v2.pdf" stays "report.v2.pdf"); a name typed without an extension keeps the file's
    /// current one. An unchanged, empty or invalid name does nothing.
    func rename(to newName: String) throws {
        guard let newURL = Self.renamedURL(for: url, typed: newName) else { return }
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
        } catch {
            logger.error("rename of \(self.url.lastPathComponent, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        update(with: newURL)
    }

    /// Where renaming `url` to the typed name moves it, or nil when nothing should happen (same
    /// name, empty, or a name that is not a single path component).
    static func renamedURL(for url: URL, typed newName: String) -> URL? {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":") else { return nil }
        let typedExtension = (name as NSString).pathExtension
        let fileName = typedExtension.isEmpty && !url.pathExtension.isEmpty && !name.hasPrefix(".")
            ? name + "." + url.pathExtension
            : name
        let newURL = url.deletingLastPathComponent().appendingPathComponent(fileName)
        return newURL.lastPathComponent == url.lastPathComponent ? nil : newURL
    }

    private func update(with newURL: URL) {
        url = newURL
        inode = Self.inode(of: newURL)
        let fileName = newURL.lastPathComponent
        if fileName != storedName { storedName = fileName }
        nameTruncated = Self.truncated(fileName)
    }

    private static func truncated(_ fileName: String) -> String {
        fileName.count < 17 ? fileName : String(fileName.prefix(6)) + "..." + String(fileName.suffix(7))
    }

    private static func inode(of url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.systemFileNumber] as? UInt64
    }

    // MARK: - Watching the parent folder

    private func startObservingFileChanges() {
        // O_EVTONLY: watch only, so the volume is not kept busy (eject / unmount)
        let fd = url.deletingLastPathComponent().path.withCString { Darwin.open($0, O_EVTONLY) }
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        let owner = WeakTrayFile(self)
        source.setEventHandler {
            MainActor.assumeIsolated {
                // re-read the name / inode of the (possibly renamed) file
                guard let file = owner.file else { return }
                file.update(with: file.url)
            }
        }
        // the descriptor is captured by value: the handler runs after deinit's cancel()
        source.setCancelHandler {
            Darwin.close(fd)
        }
        fileSystemSource = source
        source.resume()
    }

    // MARK: - Hashable (by inode)

    func hash(into hasher: inout Hasher) {
        if let inode {
            hasher.combine(1 as UInt8)
            hasher.combine(inode)
        } else {
            hasher.combine(0 as UInt8)
        }
    }

    static func == (lhs: TrayFile, rhs: TrayFile) -> Bool {
        lhs.inode == rhs.inode
    }
}

/// Weak reference to a TrayFile for its dispatch-source handler, which runs on the main queue.
private final class WeakTrayFile: @unchecked Sendable {
    weak var file: TrayFile?
    init(_ file: TrayFile) { self.file = file }
}
