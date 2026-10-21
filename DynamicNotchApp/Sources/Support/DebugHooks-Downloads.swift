// F8: DEBUG-only commands of the Downloads widget (2026-10-20), registered with
// DebugCommandRegistry by DebugHooks.install (`DownloadsWidgetDebug.install()`):
//   dllog                 log the watcher state and the listed items ("[Downloads] …")
//   dlpreview:<dir>       write <dir>/downloads-<live|sample|progress|empty|denied|confirm>-<dark|light>.png
//                         (the widget offscreen at 5 cells × 202 pt; `sample` = finished files,
//                         `progress` = determinate / indeterminate / stopped downloads + files),
//                         downloads-notch-<determinate|indeterminate>.png (the closed-notch
//                         indicator on black) and downloads-settings-<dark|light>.png (520 pt).
//                         WidgetSnapshotter options apply (`<dir>?appearance=dark&settle=3`).
//   dlclearplan           compute the Clear Old plan of the watched folder and log it (the widget
//                         shows its confirmation; nothing is moved)
//   dlclearcancel         dismiss the confirmation
//   dlclearconfirm        confirm the shown plan (moves the items to the Trash — use a scratch folder)
// Nothing else is written except the PNGs.
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum DownloadsWidgetDebug {
    static func install() {
        let r = DebugCommandRegistry.self
        let w = DownloadsWatcher.shared
        r.register("dllog", "log the Downloads watcher state and its items") { _ in log() }
        r.register("dlpreview", usage: "dlpreview:<dir>", "Downloads widget live / sample / progress / empty / denied / confirm + notch indicator + settings") { arg in
            w.start(holdFor: 30)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                log()
                WidgetSnapshotter.session(arg, tag: "[Downloads]") { preview(to: $0) }
            }
        }
        r.register("dlclearplan", "compute the Clear Old plan of the watched folder (shows the confirmation)") { _ in
            w.prepareClear()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let plan = w.clearPlan
                NSLog("[Downloads] clear plan: %ld items, %lld bytes, %ld days: %@", plan?.urls.count ?? -1,
                      plan?.bytes ?? 0, plan?.days ?? 0, (plan?.urls.map(\.lastPathComponent) ?? []).joined(separator: ", "))
            }
        }
        r.register("dlclearcancel", "dismiss the Clear Old confirmation") { _ in w.cancelClear() }
        r.register("dlclearconfirm", "confirm the shown Clear Old plan (moves items to the Trash)") { _ in w.confirmClear() }
    }

    private static func log() {
        let w = DownloadsWatcher.shared
        NSLog("[Downloads] %@", w.debugDescription)
        for item in w.items {
            NSLog("[Downloads] %@ | %@ | size=%lld | added=%@ | partial=%@ | %@", item.url.lastPathComponent, item.name,
                  item.size ?? -1, item.added.description, item.partial?.rawValue ?? "-",
                  w.progress[item.id].map(DownloadsFormat.progressDetail) ?? "")
        }
    }

    static func sample(now: Date) -> [DownloadItem] {
        let dir = URL(fileURLWithPath: "/Users/Shared/Downloads-preview", isDirectory: true)
        func item(_ name: String, _ size: Int64?, ago: TimeInterval, dir isDir: Bool = false,
                  partial: DownloadItem.Partial? = nil, shown: String? = nil) -> DownloadItem {
            DownloadItem(url: dir.appendingPathComponent(name), name: shown ?? name, size: size,
                         added: now.addingTimeInterval(-ago), modified: now.addingTimeInterval(-ago),
                         isDirectory: isDir, isPackage: false, partial: partial)
        }
        return [
            item("Xcode_26.6.xip.download", 3_100_000_000, ago: 5, dir: true, partial: .safari, shown: "Xcode_26.6.xip"),
            item("dataset.zip.crdownload", 48_200_000, ago: 3, partial: .chromium, shown: "dataset.zip"),
            item("old-installer.dmg.part", 12_000_000, ago: 4000, partial: .firefox, shown: "old-installer.dmg"),
            item("Invoice-2026-10.pdf", 182_000, ago: 120),
            item("IMG_4021.HEIC", 2_400_000, ago: 3600 * 3),
            item("Design Review.key", 18_700_000, ago: 86_400 * 2),
            item("Photos", 640_000_000, ago: 86_400 * 9, dir: true),
        ]
    }

    static func sampleProgress(_ items: [DownloadItem]) -> [String: DownloadProgress] {
        [
            items[0].id: DownloadProgress(fraction: 0.42, bytes: 1_302_000_000, totalBytes: 3_100_000_000,
                                          bytesPerSecond: 24_500_000, isStalled: false),
            items[1].id: DownloadProgress(fraction: nil, bytes: 48_200_000, totalBytes: nil,
                                          bytesPerSecond: 3_100_000, isStalled: false),
            items[2].id: DownloadProgress(fraction: nil, bytes: 12_000_000, totalBytes: nil,
                                          bytesPerSecond: nil, isStalled: true),
        ]
    }

    private static func preview(to dir: URL) {
        let now = Date()
        let all = sample(now: now)
        let files = Array(all.dropFirst(3))
        let cases: [(String, DownloadsPreviewState?)] = [
            ("live", nil),
            ("sample", DownloadsPreviewState(items: files, now: now)),
            ("progress", DownloadsPreviewState(items: all, progress: sampleProgress(all), now: now)),
            ("empty", DownloadsPreviewState(items: [], now: now)),
            ("denied", DownloadsPreviewState(items: [], status: .denied, now: now)),
            ("confirm", DownloadsPreviewState(items: files, clearPlan: .init(urls: files.map(\.url), bytes: 661_282_000, days: 30), now: now)),
        ]
        let width = DownloadsWidgetLayout.cells * NookWidgetLayout.cell
        for (name, state) in cases {
            // live rows load Quick Look thumbnails asynchronously: give them time
            WidgetSnapshotter.widget("downloads-\(name)", in: dir, width: width, alignment: .top,
                                     settle: state == nil ? 2.5 : 0.5) {
                DownloadsWidgetView(preview: state, tracksVisibility: false)
            }
        }
        let notch = CGSize(width: 185, height: 32)
        let notchCases: [(String, DownloadProgress)] = [
            ("determinate", DownloadProgress(fraction: 0.42, bytes: 1_302_000_000, totalBytes: 3_100_000_000, bytesPerSecond: nil, isStalled: false)),
            ("indeterminate", DownloadProgress(fraction: nil, bytes: 48_200_000, totalBytes: nil, bytesPerSecond: nil, isStalled: false)),
        ]
        for (name, p) in notchCases {
            let side = DownloadsClosedNotchIndicator.sideWidth(notchHeight: notch.height)
            let size = CGSize(width: notch.width + 2 * side, height: notch.height)
            let view = DownloadsClosedNotchIndicator(notchSize: notch, preview: p)
                .frame(width: size.width, height: size.height)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
            WidgetSnapshotter.write(view, size: size, dark: true, to: dir.appendingPathComponent("downloads-notch-\(name).png"))
        }
        WidgetSnapshotter.settings("downloads-settings", in: dir, size: CGSize(width: 520, height: 560)) {
            DownloadsWidgetSettingsView(tracksVisibility: false)
        }
    }
}
#endif
