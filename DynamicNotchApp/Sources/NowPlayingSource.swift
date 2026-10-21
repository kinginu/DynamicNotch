// NowPlayingSource — an app that reports now-playing information (MediaManager.nowPlayingSources,
// shown by SourceChipView).
import Foundation

struct NowPlayingSource: Equatable, Hashable, Identifiable {
    var bundleIdentifier: String
    var appName: String
    var pid: Int

    var id: String { bundleIdentifier.isEmpty ? "\(appName)#\(pid)" : bundleIdentifier }

    /// Name shown in the chip's tooltip.
    var displayName: String { appName.isEmpty ? bundleIdentifier : appName }

    /// SF Symbol of the chip.
    var iconName: String { "music.note" }

    /// Whether this is MediaManager's active source.
    @MainActor var isActive: Bool { MediaManager.shared.activeSource?.id == id }
}
