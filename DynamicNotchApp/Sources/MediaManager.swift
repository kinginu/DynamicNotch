// MediaManager — now-playing state and transport controls for the media widget, the mini player
// and the media live activity.
//
// Now-playing information comes from MediaRemoteAdapter (ejbills/mediaremote-adapter): its helper
// process can read MediaRemote, which refuses unentitled apps since macOS 15.4, and it delivers
// every update on the main queue. Transport commands go through the adapter too (system-wide
// source) or through AppleScript (`preferredMediaSource` Music / Spotify).
//
// Lifecycle: the listener is restarted with exponential backoff (1…16 s) when the helper exits and
// 0.5 s after an app launch or a system wake; a generation counter drops callbacks of a previous
// listener. When the playing app quits (checked every 10 s) or playback stays paused for 15 s, the
// state is reset and the media live activity removed.
import AppKit
import Foundation
import MediaRemoteAdapter
import Observation
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "media")

@MainActor
@Observable
final class MediaManager {
    static let shared = MediaManager()

    // MARK: Now-playing state

    /// Elapsed time at `elapsedTimeAnchor` (seconds).
    var elapsedTime: Double = 0
    var duration: Double? = nil
    /// Apps that report now-playing information (at most the adapter's current one).
    var nowPlayingSources: [NowPlayingSource] = []
    /// Bundle identifier of the source the user picked, if any.
    var userPinnedClientID: String? = nil
    var preferredMediaSource: MediaSource = .systemWide
    var track: Track = Track()

    var isPlaying: Bool {
        get { _isPlaying }
        set {
            guard newValue != _isPlaying else { return }
            playStateWillChange(to: newValue)
            _isPlaying = newValue
        }
    }
    private var _isPlaying = false

    /// When `elapsedTime` was last set.
    private(set) var elapsedTimeAnchor: Date = Date()

    /// Average colour of the current artwork (AudioAnimationView's automatic tint), computed once
    /// per artwork.
    var albumArtAverageColor: NSColor? = nil

    // MARK: Private state

    @ObservationIgnored private var mediaController = MediaRemoteAdapter.MediaController()
    /// Bumped for every new listener; callbacks of older listeners are ignored.
    @ObservationIgnored private var listenerGeneration = 0
    @ObservationIgnored private var listenerRecoveryAttempt = 0
    @ObservationIgnored private var listenerRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var appRunningCheckTimer: Timer?
    @ObservationIgnored private var workspaceObserverTokens: [NSObjectProtocol] = []
    /// Last TrackInfo received from the adapter (also the source of `nowPlayingSources`).
    @ObservationIgnored private var lastReceivedTrackInfo: MediaRemoteAdapter.TrackInfo?
    /// Encoded artwork (base64 from the adapter payload) of `track.albumArtImage`.
    @ObservationIgnored private var lastArtworkKey: String?
    /// Track updates are dropped until then (right after "pause and dismiss").
    @ObservationIgnored private var ignoreTrackUpdatesUntil = Date(timeIntervalSince1970: 0)
    /// AppleScript → last run time; the same script runs at most every 2 s.
    @ObservationIgnored private var scriptCooldowns: [String: Date] = [:]

    private static let pauseDismissTimerName = "pauseDismissIdle"
    private static let recoveryDelays: [Double] = [1, 2, 4, 8, 16]

    // App-lifetime singleton: observers, timers and the listener are never torn down.
    private init() {
        observeMediaEnvironmentChanges()
        reconfigureMediaController()
    }

    // MARK: - Derived state

    /// Elapsed time now: extrapolated from the anchor while playing (clamped to the duration).
    var currentElapsedTime: Double {
        guard _isPlaying else { return elapsedTime }
        let value = Date().timeIntervalSince(elapsedTimeAnchor) + elapsedTime
        if let duration, value > duration { return duration }
        return value
    }

    /// The pinned source, else the source of the current track, else the first one.
    var activeSource: NowPlayingSource? {
        if let pinned = userPinnedClientID {
            return nowPlayingSources.first { $0.bundleIdentifier == pinned } ?? nowPlayingSources.first
        }
        let appName = track.appName
        if !appName.isEmpty, let source = nowPlayingSources.first(where: { $0.appName == appName }) {
            return source
        }
        return nowPlayingSources.first
    }

    // MARK: - Transport

    func togglePlayPause() {
        if preferredMediaSource == .systemWide {
            isPlaying.toggle() // optimistic; the adapter's next update confirms it
            mediaController.togglePlayPause()
        } else {
            runAppleScript("tell application \"\(preferredMediaSourceName)\" to playpause")
        }
    }

    func goToNextTrack() {
        if preferredMediaSource == .systemWide {
            mediaController.nextTrack()
        } else {
            runAppleScript("tell application \"\(preferredMediaSourceName)\" to next track")
        }
    }

    func goToPreviousTrack() {
        if preferredMediaSource == .systemWide {
            mediaController.previousTrack()
        } else {
            runAppleScript("tell application \"\(preferredMediaSourceName)\" to previous track")
        }
    }

    /// Pauses playback and clears the now-playing state (updates in the next 1.25 s are ignored, so
    /// the paused track does not reappear right away).
    func pauseAndDismiss() {
        ignoreTrackUpdatesUntil = Date().addingTimeInterval(1.25)
        if preferredMediaSource == .systemWide {
            mediaController.pause()
        } else {
            runAppleScript("tell application \"\(preferredMediaSourceName)\" to pause")
        }
        if isPlaying { isPlaying = false }
        resetData()
    }

    /// Scrubber seek.
    func seek(to seconds: Double) {
        let target = max(0, duration.map { min(seconds, $0) } ?? seconds)
        mediaController.setTime(seconds: target)
        elapsedTime = target
        elapsedTimeAnchor = Date()
    }

    /// Opens (activates) the app that plays the current track.
    func openApp() {
        SystemAppMeta(bundleId: track.bundleIdentifier).openApp()
    }

    // MARK: - Reset

    /// Resets the state when the playing app is no longer running. Returns true when there is no
    /// track to keep (no app, or the app quit).
    @discardableResult
    func resetIfNeeded() -> Bool {
        let bundleID = track.bundleIdentifier
        if bundleID.isEmpty { return true }
        if isAppRunning(bundleID) { return false }
        resetData()
        return true
    }

    /// Clears the now-playing state and removes the media live activity.
    func resetData() {
        if track != Track.empty { track = Track.empty }
        if _isPlaying { isPlaying = false }
        if elapsedTime != 0 {
            elapsedTime = 0
        } else {
            elapsedTimeAnchor = Date()
        }
        if duration != nil { duration = nil }
        if !nowPlayingSources.isEmpty { nowPlayingSources = [] }
        if albumArtAverageColor != nil { albumArtAverageColor = nil }
        appRunningCheckTimer?.invalidate()
        appRunningCheckTimer = nil
        if userPinnedClientID != nil { userPinnedClientID = nil }
        ActiveLiveActivitiesManager.shared.removeSync(.media)
    }

    /// Derives the now-playing source from the adapter's last payload (MediaRemote's own client
    /// enumeration is blocked for unentitled apps on macOS 15.4+).
    func refreshNowPlayingClients() {
        var sources: [NowPlayingSource] = []
        if let p = lastReceivedTrackInfo?.payload,
           !(p.bundleIdentifier ?? "").isEmpty || !(p.applicationName ?? "").isEmpty {
            sources = [NowPlayingSource(bundleIdentifier: p.bundleIdentifier ?? "",
                                        appName: p.applicationName ?? "",
                                        pid: Int(p.PID ?? 0))]
        }
        if sources != nowPlayingSources { nowPlayingSources = sources }
    }

    // MARK: - Listener lifecycle

    /// Starts a fresh adapter listener on the next main-queue turn.
    func reconfigureMediaController() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.startFreshMediaController(resetState: false, resetRecoveryAttempts: false)
            }
        }
    }

    private func startFreshMediaController(resetState: Bool, resetRecoveryAttempts: Bool) {
        listenerRecoveryTask?.cancel()
        listenerRecoveryTask = nil
        if resetRecoveryAttempts { listenerRecoveryAttempt = 0 }

        listenerGeneration += 1
        let generation = listenerGeneration
        mediaController.stopListening()
        if resetState { resetData() }

        let controller = MediaRemoteAdapter.MediaController()
        mediaController = controller
        // The adapter invokes both callbacks on the main queue.
        controller.onTrackInfoReceived = { [weak self] info in
            MainActor.assumeIsolated {
                guard let self, generation == self.listenerGeneration else { return }
                if let info {
                    self.handleTrackInfoUpdate(info)
                } else {
                    // nil from the adapter: nothing is loaded in any player
                    self.lastReceivedTrackInfo = nil
                    self.resetData()
                }
                self.refreshNowPlayingClients()
            }
        }
        controller.onListenerTerminated = { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleListenerRecovery(afterGeneration: generation)
            }
        }
        controller.startListening()
    }

    /// Restarts the listener after it exited, backing off 1, 2, 4, 8, 16 s.
    private func scheduleListenerRecovery(afterGeneration generation: Int) {
        guard generation == listenerGeneration else { return }
        let delay = Self.recoveryDelays[min(listenerRecoveryAttempt, Self.recoveryDelays.count - 1)]
        listenerRecoveryAttempt += 1
        logger.notice("media listener exited; restarting in \(delay, format: .fixed(precision: 0)) s")
        restartListener(after: delay)
    }

    /// An app launched or the Mac woke: restart the listener shortly.
    private func scheduleEnvironmentRecovery() {
        restartListener(after: 0.5)
    }

    private func restartListener(after delay: Double) {
        listenerRecoveryTask?.cancel()
        listenerRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.startFreshMediaController(resetState: true, resetRecoveryAttempts: false)
        }
    }

    private func observeMediaEnvironmentChanges() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didWakeNotification] {
            workspaceObserverTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleEnvironmentRecovery() }
            })
        }
    }

    // MARK: - Track updates

    private func handleTrackInfoUpdate(_ info: MediaRemoteAdapter.TrackInfo) {
        lastReceivedTrackInfo = info
        guard Date() >= ignoreTrackUpdatesUntil else { return }
        let p = info.payload
        let newDuration = p.durationMicros.map { $0 / 1_000_000 }
        if newDuration != duration { duration = newDuration }
        if let elapsed = p.currentElapsedTime ?? p.elapsedTimeMicros.map({ $0 / 1_000_000 }) {
            if elapsed != elapsedTime { elapsedTime = elapsed }
            elapsedTimeAnchor = Date()
        }
        updateTrackInfo(title: p.title, artist: p.artist, album: p.album, isPlaying: p.isPlaying ?? false,
                        albumArtImage: p.artwork, artworkKey: p.artworkDataBase64,
                        appName: p.applicationName, bundleIdentifier: p.bundleIdentifier)
    }

    private func updateTrackInfo(title: String?, artist: String?, album: String?, isPlaying: Bool,
                                 albumArtImage: NSImage?, artworkKey: String?,
                                 appName: String?, bundleIdentifier: String?) {
        if let title {
            // Keep the previous artwork object when the bytes did not change: the adapter decodes a
            // new NSImage per event and Track equality compares artwork by identity. Compared by the
            // payload's encoded artwork (cheap), not by encoding both images.
            var artwork = albumArtImage
            if let old = track.albumArtImage, let new = artwork, old !== new,
               let artworkKey, artworkKey == lastArtworkKey {
                artwork = old
            }
            lastArtworkKey = artwork == nil ? nil : artworkKey
            var newTrack = Track()
            newTrack.title = title
            newTrack.artist = artist ?? ""
            newTrack.album = album ?? ""
            newTrack.albumArtImage = artwork
            newTrack.appName = appName ?? ""
            newTrack.bundleIdentifier = bundleIdentifier ?? ""
            if newTrack != track {
                if newTrack.albumArtImage !== track.albumArtImage {
                    albumArtAverageColor = newTrack.albumArtImage.flatMap(Self.averageColor(of:))
                }
                track = newTrack
            }
            if appRunningCheckTimer == nil { startAppRunningMonitor() }
        }
        if isPlaying != self.isPlaying {
            self.isPlaying = isPlaying
        }
        updateLiveActivities()
    }

    /// Paused for 15 s → reset (dismisses the media live activity); playing again cancels it.
    private func playStateWillChange(to playing: Bool) {
        if playing {
            TimersManager.shared.removeTimer(Self.pauseDismissTimerName)
        } else {
            TimersManager.shared.addTimer(Self.pauseDismissTimerName, delay: 15) { [weak self] in
                self?.resetData()
            }
        }
    }

    private func updateLiveActivities() {
        let manager = ActiveLiveActivitiesManager.shared
        if track != Track.empty, _isPlaying {
            manager.insertSync(.media)
        } else {
            manager.removeSync(.media)
        }
    }

    // MARK: - App-running monitor

    /// Every 10 s: reset when the playing app has quit.
    private func startAppRunningMonitor() {
        appRunningCheckTimer?.invalidate()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.resetIfNeeded() }
        }
        RunLoop.main.add(timer, forMode: .common)
        appRunningCheckTimer = timer
    }

    /// True when an app with bundle identifier `search` runs (or one whose name contains it).
    private func isAppRunning(_ search: String) -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: search).isEmpty { return true }
        return NSWorkspace.shared.runningApplications.contains { $0.localizedName?.contains(search) == true }
    }

    // MARK: - AppleScript (Music / Spotify sources)

    private var preferredMediaSourceName: String {
        switch preferredMediaSource {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .systemWide: return ""
        }
    }

    /// Runs `script` with osascript, without waiting (the same script at most every 2 s).
    private func runAppleScript(_ script: String) {
        let now = Date()
        if let last = scriptCooldowns[script], now.timeIntervalSince(last) < 2 { return }
        scriptCooldowns[script] = now

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.terminationHandler = { process in
            if process.terminationStatus != 0 {
                logger.error("AppleScript exited with status \(process.terminationStatus): \(script, privacy: .public)")
            }
        }
        do {
            try task.run()
        } catch {
            logger.error("AppleScript failed to start: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Artwork colour

extension MediaManager {
    /// Average colour of an image (1×1 downsample); nil for (nearly) fully transparent images.
    nonisolated static func averageColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = CGFloat(pixel[3]) / 255
        guard alpha > 0.05 else { return nil }
        return NSColor(srgbRed: CGFloat(pixel[0]) / 255 / alpha, green: CGFloat(pixel[1]) / 255 / alpha,
                       blue: CGFloat(pixel[2]) / 255 / alpha, alpha: 1)
    }
}
