// Meeting — a video-conference link found in a calendar event (`detectMeetings(in:)`,
// FreeFunctions.swift); CalendarEventView shows a Join button for it.
import Foundation

struct Meeting {
    /// Join URL.
    let url: URL
    /// Conferencing service the URL belongs to.
    let service: VideoConferenceService
}
