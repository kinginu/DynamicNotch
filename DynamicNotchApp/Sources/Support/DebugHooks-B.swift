// DEBUG-only DebugHooks commands of the live activities and media (registered with
// DebugCommandRegistry by DebugHooks.install).
//   la:<activity>       force a live activity on (media, tray, calendar, batteryStatus, timerExpired,
//                       bluetoothDevice, volume, updateAvailable, fanAlert) — bypasses the producers
//   la:-<activity>      force it off
//   la:clear            remove every requested activity
//   la:state            print the live-activity state (requested / visible / current / battery / media)
//   media:toggle|next|prev   send a transport command (do not use on the user's own playback)
#if DEBUG
import AppKit
import SwiftUI

extension DebugHooks {
    @MainActor static func registerCommandsB() {
        let r = DebugCommandRegistry.self
        r.register("la", usage: "la:<activity>|-<activity>|clear|state", "force a live activity on/off, clear, or print the state") { arg in
            let center = LiveActivityCenter.shared
            switch arg {
            case "clear":
                center.debugClear()
            case "state":
                NSLog("%@", "[DebugHooks-B] \(center.debugDescription)")
            default:
                let off = arg.hasPrefix("-")
                let raw = off ? String(arg.dropFirst()) : arg
                guard let activity = LiveActivity(rawValue: raw == "battery" ? "batteryStatus" : raw) else {
                    NSLog("%@", "[DebugHooks-B] unknown activity \(raw)")
                    return
                }
                center.debugForce(activity, on: !off)
            }
            NSLog("%@", "[DebugHooks-B] \(center.debugDescription)")
        }
        r.register("media", usage: "media:toggle|next|prev|state", "send a transport command (not on the user's own playback) and log the track") { arg in
            let m = MediaManager.shared
            switch arg {
            case "toggle": m.togglePlayPause()
            case "next": m.goToNextTrack()
            case "prev": m.goToPreviousTrack()
            default: break
            }
            NSLog("%@", "[DebugHooks-B] media title=\(m.track.title) artist=\(m.track.artist) playing=\(m.isPlaying) elapsed=\(Int(m.currentElapsedTime)) duration=\(m.duration ?? -1) art=\(m.track.albumArtImage != nil) sources=\(m.nowPlayingSources.map(\.appName))")
        }
    }
}
#endif
