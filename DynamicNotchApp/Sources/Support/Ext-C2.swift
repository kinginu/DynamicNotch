// Tray helpers: Quick Look thumbnails for tray icons, the Quick Look panel data source, and the
// tray files' context menu.
import AppKit
import Quartz
import QuickLookThumbnailing

// MARK: - Thumbnails

/// QuickLook thumbnails for tray icons, cached by path + modification date + size.
@MainActor
enum TrayThumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func thumbnail(for url: URL, side: CGFloat) async -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)|\(side)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: scale, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil // no thumbnail for this type: the Finder icon stays
        }
        let image = rep.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Quick Look

/// Quick Look data source for the tray (Space in the tray, "Quick Look" in the context menu).
@MainActor
final class TrayQuickLookSource: NSObject, QLPreviewPanelDataSource {
    static let shared = TrayQuickLookSource()
    private var urls: [URL] = []

    func show(_ urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        // above the notch window (mainMenu + 3)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    // The panel calls its data source on the main thread.
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let url: URL? = MainActor.assumeIsolated { urls.indices.contains(index) ? urls[index] : nil }
        return url.map { $0 as NSURL }
    }
}

// MARK: - Context menus

/// NSMenuItem running a closure (context menus built for CustomDraggableView).
final class TrayClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, systemImage: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        self.target = self
        if let systemImage { self.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

extension Tray {
    /// Context menu for one or more tray files.
    func contextMenu(for targets: [TrayFile], stackID: UUID? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(TrayClosureMenuItem(String(localized: "Open"), systemImage: "arrow.up.forward.app") { [weak self] in
            self?.open(targets)
        })
        menu.addItem(TrayClosureMenuItem(String(localized: "Quick Look"), systemImage: "eye") {
            TrayQuickLookSource.shared.show(targets.map(\.url))
        })
        menu.addItem(TrayClosureMenuItem(String(localized: "Show in Finder"), systemImage: "folder") { [weak self] in
            self?.revealInFinder(targets)
        })
        menu.addItem(.separator())
        menu.addItem(TrayClosureMenuItem(String(localized: "Copy"), systemImage: "doc.on.doc") { [weak self] in
            self?.copyToClipboard(targets)
        })
        if targets.count == 1, stackID == nil, let file = targets.first, canRename(file) {
            menu.addItem(TrayClosureMenuItem(String(localized: "Rename"), systemImage: "pencil") { [weak self] in
                self?.beginRenaming(file)
            })
        }
        if let stackID {
            menu.addItem(TrayClosureMenuItem(String(localized: "Unstack"), systemImage: "square.stack.3d.down.right") { [weak self] in
                self?.unstack(stackID)
            })
        }
        menu.addItem(TrayClosureMenuItem(String(localized: "Send via AirDrop"), systemImage: "antenna.radiowaves.left.and.right") { [weak self] in
            self?.airDrop(targets)
        })
        menu.addItem(.separator())
        menu.addItem(TrayClosureMenuItem(String(localized: "Remove from tray"), systemImage: "xmark.circle") { [weak self] in
            self?.remove(targets)
        })
        return menu
    }
}
