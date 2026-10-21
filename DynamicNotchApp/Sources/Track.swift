// Track — the now-playing track as MediaManager publishes it (`MediaManager.track`). Equality
// compares the artwork by identity (MediaManager keeps the same NSImage while the bytes do not
// change), so views redraw the artwork only when it really changed.
import AppKit

struct Track: Hashable {
    var id: String = ""
    var metaId: String = ""
    var artist: String = ""
    var title: String = ""
    var isValid: Bool = false
    var albumTitle: String = ""
    var size: Int = 0

    var album: String = ""
    var albumArtImage: NSImage? = nil
    var appName: String = ""
    var bundleIdentifier: String = ""
    var isPlaying: Bool = false

    /// No track (MediaManager's reset state).
    static let empty = Track()

    /// Composite identifier used to group a track's artwork / animations.
    var albumId: String {
        artist + title + (isValid ? "true" : "false") + String(size)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id + metaId + artist + title + (isValid ? "true" : "false") + albumId + albumTitle)
        hasher.combine(album + appName + bundleIdentifier)
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id && lhs.metaId == rhs.metaId && lhs.artist == rhs.artist &&
        lhs.title == rhs.title && lhs.isValid == rhs.isValid && lhs.albumTitle == rhs.albumTitle &&
        lhs.size == rhs.size && lhs.album == rhs.album && lhs.appName == rhs.appName &&
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.isPlaying == rhs.isPlaying &&
        lhs.albumArtImage === rhs.albumArtImage
    }
}
