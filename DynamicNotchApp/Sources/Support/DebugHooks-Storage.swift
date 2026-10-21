// DEBUG-only commands of the Storage widget (2026-10-20), registered with DebugCommandRegistry
// by DebugHooks.install (`StorageWidgetDebug.install()`, also still called when the widget appears,
// only re-registers):
//   storagelog            log every volume the manager reads ("[Storage] …")
//   storagepreview:<dir>  write <dir>/storage-<live|sample|one|many|empty>[-pct]-<dark|light>.png
//                         (the widget offscreen at 4 cells × 202 pt; `sample` = 4 example volumes,
//                         `one` = a single volume, `many` = 6 → scrolls, `-pct` = percent mode) and
//                         storage-settings-<dark|light>.png (Settings ▸ Widgets ▸ Storage at 520 pt).
// Nothing is ejected, applied or written except the PNGs.
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum StorageWidgetDebug {
    static func install() {
        DebugCommandRegistry.register("storagelog", "log every volume the manager reads") { _ in log() }
        DebugCommandRegistry.register("storagepreview", usage: "storagepreview:<dir>", "Storage widget live / sample / one / many / empty (+ -pct) + settings") { arg in
            StorageVolumesManager.shared.start()
            StorageVolumesManager.shared.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                log()
                WidgetSnapshotter.session(arg, tag: "[Storage]") { preview(to: $0) }
            }
        }
    }

    private static func log() {
        for v in StorageVolumesManager.readVolumes() {
            NSLog("[Storage] %@ | %@ | %@ | %@ | total=%lld avail=%lld used=%ld%% ejectable=%d",
                  v.id, v.name, v.url.path, v.kind.rawValue, v.totalBytes, v.availableBytes, v.usedPercent, v.isEjectable)
        }
    }

    static let gb: Int64 = 1_000_000_000
    static let sample: [StorageVolume] = [
        StorageVolume(id: "s1", name: "Macintosh HD", url: URL(fileURLWithPath: "/"), kind: .internalDisk,
                      totalBytes: 994 * gb, availableBytes: 412 * gb, isEjectable: false),
        StorageVolume(id: "s2", name: "Backup", url: URL(fileURLWithPath: "/Volumes/Backup"), kind: .external,
                      totalBytes: 2000 * gb, availableBytes: 180 * gb, isEjectable: true),
        StorageVolume(id: "s3", name: "Install macOS", url: URL(fileURLWithPath: "/Volumes/Install macOS"), kind: .diskImage,
                      totalBytes: 16 * gb, availableBytes: 1 * gb / 2, isEjectable: true),
        StorageVolume(id: "s4", name: "Home on NAS", url: URL(fileURLWithPath: "/Volumes/Home"), kind: .network,
                      totalBytes: 4000 * gb, availableBytes: 2900 * gb, isEjectable: true),
    ]

    private static func preview(to dir: URL) {
        let many = sample + [
            StorageVolume(id: "s5", name: "Photos SSD", url: URL(fileURLWithPath: "/Volumes/Photos"), kind: .external,
                          totalBytes: 1000 * gb, availableBytes: 90 * gb, isEjectable: true),
            StorageVolume(id: "s6", name: "Audio CD", url: URL(fileURLWithPath: "/Volumes/Audio CD"), kind: .optical,
                          totalBytes: 700_000_000, availableBytes: 0, isEjectable: true),
        ]
        let cases: [(String, [StorageVolume]?, StorageDisplayMode?)] = [
            ("live", nil, nil), ("sample", sample, .gigabytes), ("sample-pct", sample, .percent),
            ("one", [sample[0]], .gigabytes), ("one-pct", [sample[1]], .percent),
            ("many", many, .gigabytes), ("empty", [], nil),
        ]
        let width = StorageWidgetLayout.cells * NookWidgetLayout.cell
        for (name, volumes, mode) in cases {
            WidgetSnapshotter.widget("storage-\(name)", in: dir, width: width) {
                StorageWidgetView(previewVolumes: volumes, previewMode: mode)
            }
        }
        WidgetSnapshotter.settings("storage-settings", in: dir, size: CGSize(width: 520, height: 560)) { StorageWidgetSettingsView() }
    }
}
#endif
