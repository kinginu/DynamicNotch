// MediaSource — where MediaManager sends transport commands: Music or Spotify (AppleScript), or
// the system-wide now-playing app (MediaRemoteAdapter).
enum MediaSource: String, CaseIterable, Codable, Equatable, Hashable {
    case music
    case spotify
    case systemWide
}
